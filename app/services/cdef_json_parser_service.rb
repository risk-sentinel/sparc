class CdefJsonParserService
  include BatchInsertable
  include ProgressTrackable

  CONTROL_ID = "control-id".freeze
  include CciNistResolvable
  include BackMatterPromotable

  def initialize(cdef_document, file_path)
    @document  = cdef_document
    @file_path = file_path
  end

  # `validate:` defaults to true so user uploads (the common case)
  # are rejected pre-commit when the import produces an invalid
  # OSCAL representation. Trusted upstream pipelines that ingest
  # third-party OSCAL (AWS Labs CDEFs, where any schema gap is
  # tracked separately and should not block ingestion) pass
  # `validate: false`.
  def parse(validate: true)
    if validate
      CdefMutationService.apply(@document) { |_doc| _parse_dispatch }
    else
      _parse_dispatch
    end
  end

  private

  def _parse_dispatch
    update_processing_stage!(:reading_file)
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)

    update_processing_stage!(:creating_records)
    case detect_json_format(data)
    when :oscal_cdef      then parse_oscal_cdef(data)
    when :inspec_profile  then parse_inspec_profile(data)
    when :stigviewer      then parse_stigviewer(data)
    else                       parse_generic(data)
    end
  end

  def detect_json_format(data)
    return :oscal_cdef     if data.key?("component-definition")
    return :inspec_profile if data.key?("profiles") || (data.key?("controls") && data.key?("version"))
    return :stigviewer     if data.key?("stigs")
    :generic
  end

  # ── OSCAL Component Definition JSON ─────────────────────────────

  def parse_oscal_cdef(data)
    cdef = data["component-definition"]
    metadata = cdef["metadata"] || {}

    # Preserve full OSCAL metadata (roles, parties, revisions, etc.)
    metadata_extra = metadata.except("title", "version", "oscal-version", "last-modified")

    @document.update!(
      cdef_type:       "custom",
      cdef_version:    metadata["version"],
      oscal_version:   metadata["oscal-version"],
      description:     metadata["title"],
      metadata_extra:  metadata_extra.presence || {},
      import_metadata: {
        "format" => "oscal_cdef",
        "uuid"   => cdef["uuid"]
      }.compact
    )
    @document.assign_oscal_uuid!(cdef["uuid"])

    # #498 slice 3 — promote OSCAL back-matter to first-class
    # BackMatterResource rows instead of stashing the raw array in
    # import_metadata. Promoted rows have source: "imported" and the
    # exporter picks them up via the normal managed_resources query.
    promote_back_matter_resources(cdef.dig("back-matter", "resources"))

    # Extract controls from components
    components = cdef["components"] || []

    # #998 — component-level props and links had nowhere to go, and
    # build_component emitted neither, so an imported CDEF's component-level
    # claims were dropped on the way back out. Props and links were already
    # carried on implemented-requirements and statements; the component was the
    # one place they were missing.
    #
    # Taken from the FIRST component because a CdefDocument exports exactly one
    # (`"components" => [ build_component ]`), built from the
    # cdef_documents.component_* columns. That is also why a validation PAIR
    # cannot be expressed in a CDEF at all — see #998, where the decision was to
    # model validation on the SSP and document CDEF as partial.
    capture_component_metadata(components.first)
    control_attrs = []
    field_entries = []
    row_order = 0

    # ir_statements parallel-tracks (idx -> ir["statements"]) so we can
    # populate cdef_control_statements after batch insert (#393).
    ir_statements_by_idx = {}

    components.each do |component|
      (component["control-implementations"] || []).each do |ci|
        (ci["implemented-requirements"] || []).each do |ir|
          idx = control_attrs.size
          attrs = {
            control_id:     ir[CONTROL_ID],
            # #912 — an OSCAL component definition references controls FROM a
            # catalog, so its identifiers are NIST by construction. Source and
            # NIST reference are the same value here; recording both keeps the
            # column meaning uniform across importers.
            source_control_id: ir[CONTROL_ID],
            source_vocabulary: "nist",
            title:          ir[CONTROL_ID],
            control_family: ir[CONTROL_ID].to_s.split("-").first.upcase.presence,
            row_order:      row_order
          }

          control_attrs << attrs
          field_entries << [ idx, "description", ir["description"] ] if ir["description"].present?
          field_entries << [ idx, "component", component["title"] ] if component["title"].present?
          field_entries << [ idx, "remarks", ir["remarks"] ] if ir["remarks"].present?
          ir_statements_by_idx[idx] = ir["statements"] if ir["statements"].present?
          row_order += 1
        end
      end
    end

    imported_ids = batch_insert_records(
      control_class: CdefControl,
      field_class:   CdefControlField,
      document_fk:   :cdef_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )

    populate_cdef_statements(imported_ids, ir_statements_by_idx)

    # #887 — build the browser index here rather than in any one importer.
    # This method is the single choke point every OSCAL CDEF passes through
    # (AWS Labs, org upload, YAML, XCCDF), and the parsed document is in hand,
    # so an org-uploaded CDEF gets the same searchable fields as the AWS corpus
    # without the source needing to be retained anywhere.
    #
    # Non-fatal: a CDEF that imports but fails to index is a degraded browser
    # row, not a failed import, and cdef:reindex can repair it.
    index_components(data)
  end

  # #998 — see the note at the call site.
  def capture_component_metadata(component)
    return if component.blank?

    props = Array(component["props"])
    links = Array(component["links"])
    return if props.empty? && links.empty?

    @document.update!(component_props_data: props, component_links_data: links)
  end

  def index_components(data)
    CdefComponentIndexer.new(@document, data).index!
  rescue StandardError => e
    Rails.logger.warn(
      "[CdefJsonParserService] component indexing failed for " \
      "cdef_document_id=#{@document&.id}: #{e.class}: #{e.message}"
    )
  end

  # #393: iterate ir["statements"][] and create cdef_control_statements.
  # Uses each batch-inserted CdefControl's UUID + the OscalUuidService
  # derivation formula so re-exports stay UUID-stable for backfilled rows;
  # the OSCAL-supplied statement UUID wins when present.
  def populate_cdef_statements(imported_ids, ir_statements_by_idx)
    return if ir_statements_by_idx.empty?

    rows = []
    cdef_controls_by_id = CdefControl.where(id: imported_ids).index_by(&:id)

    ir_statements_by_idx.each do |idx, statements|
      cdef_control_id = imported_ids[idx]
      cdef_control = cdef_controls_by_id[cdef_control_id]
      next unless cdef_control

      Array(statements).each_with_index do |stmt, stmt_idx|
        stmt_id = stmt["statement-id"]
        next if stmt_id.blank?

        rows << {
          cdef_control_id:        cdef_control_id,
          uuid:                   stmt["uuid"].presence ||
                                  OscalUuidService.derived(cdef_control.uuid, "cdef-statement", stmt_id),
          statement_id:           stmt_id,
          implementation_prose:   stmt["description"].presence || stmt["remarks"].presence,
          remarks:                stmt["remarks"],
          set_parameters_data:    stmt["set-parameters"] || [],
          row_order:              stmt_idx
        }.compact
      end
    end

    return if rows.empty?
    CdefControlStatement.insert_all(rows.map { |r| r.merge(created_at: Time.current, updated_at: Time.current) })
  end

  # ── InSpec Profile JSON ──────────────────────────────────────────

  def parse_inspec_profile(data)
    profiles = data["profiles"] || [ data ]
    profile  = profiles.first

    @document.update!(
      cdef_type:       "custom",
      cdef_version:    profile["version"],
      description:     profile["summary"] || profile["title"],
      import_metadata: { "format" => "inspec", "name" => profile["name"] }.compact
    )

    control_attrs = []
    field_entries = []
    row_order     = 0

    (profile["controls"] || data["controls"] || []).each do |ctrl|
      # Resolve NIST control ID from tags.nist, Converter, or CCI fallback
      nist_tags = Array(ctrl.dig("tags", "nist"))
      cci_refs  = Array(ctrl.dig("tags", "cci"))
      original_id = ctrl["id"]
      stig_rule   = extract_sv_id(original_id).present?

      nist_id = if nist_tags.any?
        normalize_nist_tag(nist_tags.first)
      elsif stig_rule
        resolve_nist_for_stig(extract_sv_id(original_id), cci_refs)
      end

      # #911 — a STIG rule that does not resolve to NIST has no control to name,
      # so `control_id` stays NULL and the rule is surfaced as unmapped; the
      # SV-ID is kept in `stig_id`. A NON-STIG InSpec control keeps its own id,
      # because that id is the only label the profile gives it and nulling it
      # would blank every row of a plain InSpec CDEF. Whether such an id belongs
      # in `control_id` at all is a lineage question, deferred to layer 2.
      fallback_id = stig_rule ? nil : original_id

      attrs = {
        # #1030 — `control_id` carries the CATALOG-ADDRESSABLE control, so it
        # joins. The mapping data is statement-level (`cm-6-b`, `pm-14-a-1`) and
        # NIST catalogs hold controls and enhancements but never statement
        # parts, so storing the reference verbatim matched no catalog control at
        # all — measured at 57% of CCI resolutions. The full statement reference
        # is not lost: it goes to the `nist_controls` field below.
        control_id:     nist_id.present? ? ControlId.control_key(nist_id) : fallback_id,
        # #912 — a STIG-derived InSpec profile records the SV-ID as its source;
        # a plain profile records its own control name. Either way the source is
        # kept verbatim and `control_id` carries only what resolved to NIST.
        source_control_id: original_id,
        source_vocabulary: stig_rule ? "disa_stig" : "nist",
        title:          ctrl["title"],
        severity:       impact_to_severity(ctrl["impact"]),
        control_family: nist_id.present? ? nist_family_from_id(nist_id) : fallback_id.to_s.split("-").first.upcase.presence,
        row_order:      row_order,
        stig_id:        original_id
      }

      fields = build_inspec_fields(ctrl)
      fields["nist_controls"] = nist_id if nist_id.present?
      idx = control_attrs.size
      control_attrs << attrs
      fields.each { |fname, fval| field_entries << [ idx, fname, fval ] }
      row_order += 1
    end

    batch_insert_records(
      control_class: CdefControl,
      field_class:   CdefControlField,
      document_fk:   :cdef_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  def build_inspec_fields(ctrl)
    fields = {}
    fields["description"]   = ctrl["desc"]                          if ctrl["desc"].present?
    fields["impact"]        = ctrl["impact"].to_s                   if ctrl["impact"].present?
    fields["rationale"]     = ctrl["rationale"]                     if ctrl["rationale"].present?
    fields["check_content"] = Array(ctrl.dig("tags", "check")).join("\n") if ctrl.dig("tags", "check").present?
    fields["fix_text"]      = Array(ctrl.dig("tags", "fix")).join("\n")   if ctrl.dig("tags", "fix").present?
    fields["nist_controls"] = Array(ctrl.dig("tags", "nist")).join(", ") if ctrl.dig("tags", "nist").present?
    fields["cci_refs"]      = Array(ctrl.dig("tags", "cci")).join(", ")  if ctrl.dig("tags", "cci").present?
    fields
  end

  # ── STIG Viewer JSON ─────────────────────────────────────────────

  def parse_stigviewer(data)
    stig = data["stigs"]&.first
    raise DocumentParseError, "No STIG data found in JSON" unless stig

    @document.update!(
      cdef_type:       "disa_stig",
      description:     stig["stig_name"],
      import_metadata: { "format" => "stigviewer" }
    )

    control_attrs = []
    field_entries = []
    row_order     = 0

    (stig["findings"] || []).each do |finding|
      # Resolve NIST control ID via Converter + CCI fallback
      vuln_num = finding["vuln_num"]
      cci_refs = Array(finding["cci_ref"]&.split(",")).map(&:strip).reject(&:blank?)
      nist_id = resolve_nist_for_stig(vuln_num, cci_refs) if vuln_num.present?

      # #911 — as in the XCCDF parser: unresolved means no control to name, and
      # `group_id` / `stig_id` below keep the V-ID.
      attrs = {
        # #1030 — see the note above: the catalog-addressable control, not the
        # statement-level reference.
        # `control_key(nil)` is "unknown", not nil — guard explicitly.
        control_id:     nist_id.present? ? ControlId.control_key(nist_id) : nil,
        source_control_id: vuln_num,
        source_vocabulary: "disa_stig",
        title:          finding["rule_title"],
        severity:       finding["severity"],
        control_family: nist_id.present? ? nist_family_from_id(nist_id) : nil,
        group_id:       vuln_num,
        rule_id:        finding["rule_id"],
        row_order:      row_order,
        stig_id:        vuln_num
      }

      fields = {}
      fields["description"]   = finding["discussion"]   if finding["discussion"].present?
      fields["fix_text"]      = finding["fix_text"]      if finding["fix_text"].present?
      fields["check_content"] = finding["check_content"] if finding["check_content"].present?
      fields["cci_refs"]      = finding["cci_ref"]       if finding["cci_ref"].present?
      fields["status"]        = finding["status"]        if finding["status"].present?
      fields["nist_controls"] = nist_id                  if nist_id.present?

      idx = control_attrs.size
      control_attrs << attrs
      fields.each { |fname, fval| field_entries << [ idx, fname, fval ] }
      row_order += 1
    end

    batch_insert_records(
      control_class: CdefControl,
      field_class:   CdefControlField,
      document_fk:   :cdef_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  # ── Generic JSON ─────────────────────────────────────────────────

  def parse_generic(data)
    @document.update!(
      cdef_type:       "custom",
      description:     data["description"] || data["title"],
      import_metadata: { "format" => "generic" }
    )

    controls_array = data["controls"] || data["rules"] || data["findings"] || []
    return if controls_array.empty?

    control_attrs = []
    field_entries = []
    row_order     = 0

    controls_array.each do |ctrl|
      attrs = {
        control_id: ctrl["id"] || ctrl["control_id"] || ctrl["rule_id"],
        title:      ctrl["title"] || ctrl["name"],
        severity:   ctrl["severity"] || ctrl["impact"],
        row_order:  row_order
      }

      field_data = ctrl.except("id", "control_id", "rule_id", "title", "name", "severity", "impact")
      idx = control_attrs.size
      control_attrs << attrs
      field_data.each do |k, v|
        val = v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
        field_entries << [ idx, k.to_s, val ] if val.present?
      end
      row_order += 1
    end

    batch_insert_records(
      control_class: CdefControl,
      field_class:   CdefControlField,
      document_fk:   :cdef_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def impact_to_severity(impact)
    return nil if impact.nil?
    case impact.to_f
    when 0.7..1.0  then "high"
    when 0.4..0.69 then "medium"
    when 0.01..0.39 then "low"
    else "info"
    end
  end

  # promote_back_matter_resources moved to BackMatterPromotable concern (#583).
end
