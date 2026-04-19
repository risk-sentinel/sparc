# Parses an OSCAL Assessment Results JSON file into the relational SAR model.
#
# Usage:
#   SarJsonParserService.new(sar_document, file_path).parse
#   # or from an already-parsed hash (used by XML parser delegation):
#   SarJsonParserService.new(sar_document, nil).parse_from_hash(data)
#
class SarJsonParserService
  include ProgressTrackable

  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)
    parse_from_hash(data)
  end

  def parse_from_hash(data)
    ar = data["assessment-results"] || raise("Invalid OSCAL Assessment Results: missing 'assessment-results' root key")

    update_processing_stage!(:creating_records)
    ActiveRecord::Base.transaction do
      update_document_metadata(ar)
      @document.assign_oscal_uuid!(ar["uuid"])
      parse_local_definitions(ar["local-definitions"])
      parse_results(ar["results"] || [])
      synthesize_controls_from_results
    end
  end

  private

  # ── Document metadata ────────────────────────────────────────────

  def update_document_metadata(ar)
    metadata   = ar["metadata"] || {}
    import_ap  = ar["import-ap"] || {}
    back_matter = ar.dig("back-matter", "resources") || []

    metadata_extra = metadata.except("title", "version", "oscal-version", "last-modified")

    @document.update!(
      creation_method:    "oscal_import",
      oscal_version:      metadata["oscal-version"],
      sar_version:        metadata["version"],
      import_ap_href:     import_ap["href"],
      metadata_extra:     metadata_extra.presence || {},
      import_metadata:    {
        "uuid"        => ar["uuid"],
        "back_matter" => back_matter
      }.compact
    )
    @document.update!(name: metadata["title"]) if metadata["title"].present?
  end

  # ── Local definitions ──────────────────────────────────────────

  def parse_local_definitions(local_defs)
    return if local_defs.blank?

    (local_defs["components"] || []).each do |comp|
      comp_status = comp["status"] || {}
      @document.sar_local_components.create!(
        uuid:                   comp["uuid"],
        component_type:         comp["type"],
        title:                  comp["title"],
        description:            extract_text(comp["description"]),
        purpose:                comp["purpose"],
        status_state:           comp_status["state"],
        status_remarks:         extract_text(comp_status["remarks"]),
        responsible_roles_data: comp["responsible-roles"] || [],
        protocols_data:         comp["protocols"] || [],
        props_data:             comp["props"] || [],
        links_data:             comp["links"] || [],
        remarks:                extract_text(comp["remarks"])
      )
    end

    extra = local_defs.except("components")
    @document.update!(local_definitions_extra: extra) if extra.present?
  end

  # ── Results ────────────────────────────────────────────────────

  def parse_results(results_array)
    results_array.each_with_index do |result, idx|
      sar_result = @document.sar_results.create!(
        uuid:                   result["uuid"] || SecureRandom.uuid,
        title:                  result["title"],
        description:            extract_text(result["description"]),
        start_time:             parse_datetime(result["start"]) || Time.current,
        end_time:               parse_datetime(result["end"]),
        reviewed_controls_data: result["reviewed-controls"] || {},
        assessment_log_data:    result["assessment-log"].is_a?(Hash) ? (result["assessment-log"]["entries"] || []) : (result["assessment-log"] || []),
        attestations_data:      result["attestations"] || [],
        props_data:             result["props"] || [],
        links_data:             result["links"] || [],
        remarks:                extract_text(result["remarks"]),
        position:               idx
      )

      # Promote first result's dates to document level
      if idx == 0
        @document.update!(
          assessment_start: sar_result.start_time,
          assessment_end:   sar_result.end_time
        )
      end

      obs_map  = parse_observations(result["observations"] || [], sar_result)
      risk_map = parse_risks(result["risks"] || [], sar_result, obs_map)
      parse_findings(result["findings"] || [], sar_result, obs_map, risk_map)
    end
  end

  # ── Observations ───────────────────────────────────────────────

  def parse_observations(observations, sar_result)
    observations.each_with_object({}) do |obs, map|
      next unless obs["uuid"].present?

      record = sar_result.sar_observations.create!(
        uuid:                   obs["uuid"],
        title:                  obs["title"],
        description:            extract_text(obs["description"]),
        collected:              parse_datetime(obs["collected"]),
        expires:                parse_datetime(obs["expires"]),
        methods_data:           obs["methods"] || [],
        types_data:             obs["types"] || [],
        origins_data:           obs["origins"] || [],
        subjects_data:          obs["subjects"] || [],
        relevant_evidence_data: obs["relevant-evidence"] || [],
        props_data:             obs["props"] || [],
        links_data:             obs["links"] || [],
        remarks:                extract_text(obs["remarks"])
      )
      map[obs["uuid"]] = record
    end
  end

  # ── Risks ──────────────────────────────────────────────────────

  def parse_risks(risks, sar_result, obs_map)
    risks.each_with_object({}) do |risk, map|
      next unless risk["uuid"].present?

      record = sar_result.sar_risks.create!(
        uuid:                    risk["uuid"],
        title:                   risk["title"],
        description:             extract_text(risk["description"]),
        statement:               extract_text(risk["statement"]),
        status:                  risk["status"],
        likelihood:              extract_facet(risk, "likelihood"),
        impact:                  extract_facet(risk, "impact"),
        deadline:                parse_datetime(risk["deadline"]),
        origins_data:            risk["origins"] || [],
        threat_ids_data:         risk["threat-ids"] || [],
        characterizations_data:  risk["characterizations"] || [],
        mitigating_factors_data: risk["mitigating-factors"] || [],
        risk_log_data:           risk["risk-log"] || {},
        remediations_data:       risk["remediations"] || [],
        props_data:              risk["props"] || [],
        links_data:              risk["links"] || [],
        remarks:                 extract_text(risk["remarks"])
      )

      (risk["related-observations"] || []).each do |ro|
        obs_record = obs_map[ro["observation-uuid"]]
        SarRiskObservation.create!(sar_risk: record, sar_observation: obs_record) if obs_record
      end

      map[risk["uuid"]] = record
    end
  end

  # ── Findings ───────────────────────────────────────────────────

  def parse_findings(findings, sar_result, obs_map, risk_map)
    findings.each do |finding|
      next unless finding["uuid"].present?

      target = finding["target"] || {}
      # When the OSCAL target points at an objective (target.type ==
      # "objective-id"), tag the finding so synthesize_controls_from_results
      # can later link it to the SarControlObjective record. We can't link
      # here because the SarControl record for the objective's parent
      # control may not exist yet.
      target_data = target.dup
      if target["type"].to_s.downcase == "objective-id" && target["target-id"].present?
        target_data["needs_objective_link"] = true
      end

      record = sar_result.sar_findings.create!(
        uuid:                          finding["uuid"],
        title:                         finding["title"],
        description:                   extract_text(finding["description"]),
        target_data:                   target_data,
        implementation_statement_uuid: finding["implementation-statement-uuid"],
        origins_data:                  finding["origins"] || [],
        props_data:                    finding["props"] || [],
        links_data:                    finding["links"] || [],
        remarks:                       extract_text(finding["remarks"])
      )

      (finding["related-observations"] || []).each do |ro|
        obs_record = obs_map[ro["observation-uuid"]]
        SarFindingObservation.create!(sar_finding: record, sar_observation: obs_record) if obs_record
      end

      (finding["related-risks"] || []).each do |rr|
        risk_record = risk_map[rr["risk-uuid"]]
        SarFindingRisk.create!(sar_finding: record, sar_risk: risk_record) if risk_record
      end
    end
  end

  # ── Control synthesis ──────────────────────────────────────────
  #
  # OSCAL Assessment Results don't have a flat "controls" structure —
  # control references live in findings (target.target-id), observation
  # props, and reviewed-controls. This method extracts unique control IDs
  # and creates SarControl records so the UI shows a meaningful count.

  def synthesize_controls_from_results
    control_data = {}
    # objectives_by_control[control_id] = Set<objective_id> -- collected so
    # we can create SarControlObjective records after the parent SarControls
    # exist. findings_to_link is [[finding, objective_id], ...] -- links are
    # set in a final pass once all objective records are in place.
    objectives_by_control = Hash.new { |h, k| h[k] = Set.new }
    findings_to_link = []

    @document.sar_results.each do |result|
      # Build obs_lookup so a finding can pull data from its related
      # observation (Checkov emits remarks like "Resource: aws.default"
      # that we want to surface on the SAR control card).
      obs_lookup = result.sar_observations.index_by(&:uuid)

      result.sar_findings.includes(:sar_observations).each do |finding|
        target = finding.target_data || {}
        target_id = target["target-id"]
        next if target_id.blank?

        ctrl_id, objective_id = split_objective_target(target_id)
        status = target.dig("status", "state") || "other"
        # parse_findings created SarFindingObservation join records from
        # the OSCAL related-observations[]; the first joined observation
        # carries the resource-level remarks Checkov emits.
        primary_obs = finding.sar_observations.first
        control_data[ctrl_id] ||= {
          status:               status,
          title:                finding.title,
          finding_description:  finding.description,
          observation_remarks:  primary_obs&.remarks,
          observation_methods:  primary_obs&.methods_data,
          collected:            primary_obs&.collected
        }

        if objective_id.present?
          objectives_by_control[ctrl_id] << objective_id
          findings_to_link << [ finding, ctrl_id, objective_id ]
        end
      end

      # Also enrich directly from observations (when a finding didn't cover
      # them) -- Checkov results use title "PASS: CKV_xxx" / "FAIL: CKV_xxx"
      # and carry the NIST control ID in props_data.
      result.sar_observations.each do |obs|
        (obs.props_data || []).each do |prop|
          next unless prop["name"] == "control-id" || prop["name"] == "nist-control"
          ctrl_id = prop["value"]
          status = obs.title&.start_with?("PASS") ? "pass" : "fail"
          control_data[ctrl_id] ||= {
            status:               status,
            title:                obs.description,
            observation_remarks:  obs.remarks,
            observation_methods:  obs.methods_data,
            collected:            obs.collected
          }
        end
      end

      # Extract from reviewed-controls in the result. include-controls may
      # carry statement-ids that name specific objectives we should track.
      reviewed = result.reviewed_controls_data || {}
      (reviewed["control-selections"] || []).each do |sel|
        (sel["include-controls"] || []).each do |ic|
          ctrl_id = ic["control-id"]
          next if ctrl_id.blank?
          control_data[ctrl_id] ||= { status: "reviewed", title: nil }
          (ic["statement-ids"] || []).each { |sid| objectives_by_control[ctrl_id] << sid }
        end
      end
    end

    # Create SarControl records and remember each by control_id for the
    # objective + finding link passes below.
    sar_controls_by_id = {}
    control_data.each_with_index do |(ctrl_id, info), idx|
      ctrl = @document.sar_controls.create!(
        control_id:    ctrl_id,
        title:         info[:title],
        section:       "assessment-results",
        subject_asset: extract_subject_asset(info[:observation_remarks]),
        row_order:     idx
      )
      populate_enrichment_fields(ctrl, info)
      sar_controls_by_id[ctrl_id] = ctrl
    end

    populate_catalog_text_fields(sar_controls_by_id)
    create_objective_records(sar_controls_by_id, objectives_by_control)
    link_findings_to_objectives(sar_controls_by_id, findings_to_link)
    enrich_from_linked_sap_or_ssp(sar_controls_by_id)
    link_findings_to_ssp_statements
  end

  # "Resource: aws.default" -> "aws.default". Checkov's standard format.
  # Also strips common prefixes like "Subject:", "Component:", "Target:".
  def extract_subject_asset(remarks)
    return nil if remarks.blank?
    remarks.to_s.sub(/\A(resource|subject|component|target)\s*:\s*/i, "").strip.presence
  end

  def populate_enrichment_fields(ctrl, info)
    # result stays the canonical OSCAL-state value (satisfied/not-satisfied/etc)
    ctrl.sar_control_fields.create!(field_name: "result", field_value: info[:status])

    # control_status is the human-readable mapping used by the Assessment
    # Context panel. Keeps existing Excel-parser vocabulary aligned.
    status_label = oscal_state_to_control_status(info[:status])
    ctrl.sar_control_fields.create!(field_name: "control_status", field_value: status_label) if status_label

    if info[:collected].present?
      ctrl.sar_control_fields.create!(
        field_name: "date",
        field_value: info[:collected].respond_to?(:iso8601) ? info[:collected].iso8601 : info[:collected].to_s
      )
    end

    methods = Array(info[:observation_methods]).compact.uniq
    if methods.any?
      ctrl.sar_control_fields.create!(
        field_name:  "test_text",
        field_value: methods.map { |m| m.to_s.upcase }.join(", ")
      )
    end

    # notes_weakness is the assessor-facing "what failed" column. For
    # failed/not-satisfied findings, the finding description is the
    # clearest summary; for others, the observation remarks add context.
    weakness = if %w[fail failed not-satisfied].include?(info[:status].to_s.downcase)
      info[:finding_description].presence || info[:observation_remarks]
    else
      info[:observation_remarks].presence
    end
    if weakness.present?
      ctrl.sar_control_fields.create!(field_name: "notes_weakness", field_value: weakness)
    end
  end

  def oscal_state_to_control_status(state)
    case state.to_s.downcase
    when "satisfied", "pass" then "Implemented"
    when "not-satisfied", "fail" then "Not Implemented"
    when "partial" then "Partially Implemented"
    when "reviewed" then "Reviewed"
    end
  end

  # Pull control statement prose from the local catalog so the Assessment
  # Context panel has a "Control Text" row even when the SAR isn't linked
  # to an SSP yet.
  def populate_catalog_text_fields(sar_controls_by_id)
    return if sar_controls_by_id.empty?

    normalized = sar_controls_by_id.keys.compact.map { |id| normalize_catalog_id(id) }.uniq
    catalog_controls = CatalogControl.where(control_id: normalized).index_by(&:control_id)

    sar_controls_by_id.each do |ctrl_id, ctrl|
      cat = catalog_controls[normalize_catalog_id(ctrl_id)]
      next unless cat
      stmt = (cat.guidance_data || {}).dig("statement") || cat.description
      next if stmt.blank?
      ctrl.sar_control_fields.create!(field_name: "control_text", field_value: stmt)
    end
  rescue StandardError => e
    Rails.logger.warn("[SarJsonParserService] catalog lookup failed: #{e.message}")
  end

  def normalize_catalog_id(id)
    id.to_s.strip.downcase
  end

  # When the SAR is linked to a SAP (sap_document_id set), chain through to
  # pull responsibility + implementation + impact statement fields from the
  # SAP's linked SSP. SAR -> SAP -> SSP gives the full traceability users
  # expect. No-op if no SAP or no SSP is linked.
  def enrich_from_linked_sap_or_ssp(sar_controls_by_id)
    ssp = resolve_linked_ssp
    return if ssp.nil?

    ssp_controls = ssp.ssp_controls.includes(:ssp_control_fields)
                                   .index_by { |c| c.control_id.to_s.strip.downcase }

    sar_controls_by_id.each do |ctrl_id, sar_ctrl|
      ssp_ctrl = ssp_controls[ctrl_id.to_s.strip.downcase]
      next unless ssp_ctrl
      fields = ssp_ctrl.ssp_control_fields.index_by(&:field_name)

      responsibility = fields["responsible_entities"]&.field_value
      if responsibility.present? && !sar_ctrl.sar_control_fields.exists?(field_name: "responsibility")
        sar_ctrl.sar_control_fields.create!(field_name: "responsibility", field_value: responsibility)
      end

      implementation = fields["implementation_statement"]&.field_value.presence ||
                       fields["implementation_summary"]&.field_value.presence
      if implementation.present? && !sar_ctrl.sar_control_fields.exists?(field_name: "implementation")
        sar_ctrl.sar_control_fields.create!(field_name: "implementation", field_value: implementation)
      end

      notes = fields["notes"]&.field_value
      if notes.present? && !sar_ctrl.sar_control_fields.exists?(field_name: "impact_statement")
        sar_ctrl.sar_control_fields.create!(field_name: "impact_statement", field_value: notes)
      end
    end
  end

  # Resolves the SSP to pull enrichment data from, in priority order:
  # directly linked SSP -> SAP's linked SSP. Returns nil if no chain.
  def resolve_linked_ssp
    return SspDocument.find_by(id: @document.ssp_document_id) if @document.ssp_document_id.present?

    sap_id = @document.sap_document_id
    return nil if sap_id.blank?
    sap = SapDocument.find_by(id: sap_id)
    return nil if sap.nil? || sap.ssp_document_id.blank?
    SspDocument.find_by(id: sap.ssp_document_id)
  end

  # OSCAL SAR finding targets use IDs like "ac-1" (control-level) or
  # "ac-1_obj.a-1" (objective-level). Split into [control_id, objective_id]
  # where objective_id is nil for control-level targets.
  def split_objective_target(target_id)
    if target_id.to_s.include?("_obj")
      ctrl_id = target_id.split("_obj", 2).first
      [ ctrl_id, target_id ]
    else
      [ target_id, nil ]
    end
  end

  def create_objective_records(sar_controls_by_id, objectives_by_control)
    return if objectives_by_control.empty?

    catalog = profile_catalog_json
    now = Time.current
    rows = []

    objectives_by_control.each do |ctrl_id, oids|
      ctrl = sar_controls_by_id[ctrl_id]
      next unless ctrl

      # Prefer catalog-derived objective records (with prose/label); fall
      # back to skeletal records when no catalog is available so the FK
      # from sar_findings is satisfiable.
      catalog_objectives = if catalog.present?
        ControlObjectiveExtractorService.objectives_for_control(catalog, ctrl_id)
      else
        []
      end
      by_id = catalog_objectives.index_by { |o| o[:objective_id] }

      oids.each_with_index do |oid, idx|
        meta = by_id[oid] || {}
        rows << {
          sar_control_id:      ctrl.id,
          uuid:                SecureRandom.uuid,
          objective_id:        oid,
          label:               meta[:label],
          parent_objective_id: meta[:parent_objective_id],
          prose:               meta[:prose],
          status:              "pending",
          row_order:           meta[:row_order] || idx,
          created_at:          now,
          updated_at:          now
        }
      end
    end

    SarControlObjective.insert_all(rows) if rows.any?
  end

  def link_findings_to_objectives(sar_controls_by_id, findings_to_link)
    return if findings_to_link.empty?

    findings_to_link.each do |finding, ctrl_id, objective_id|
      ctrl = sar_controls_by_id[ctrl_id]
      next unless ctrl
      objective = ctrl.sar_control_objectives.find_by(objective_id: objective_id)
      next unless objective
      finding.update_columns(sar_control_objective_id: objective.id)
      # Strip the needs_objective_link flag now that linkage is satisfied.
      td = finding.target_data || {}
      if td["needs_objective_link"]
        finding.update_columns(target_data: td.except("needs_objective_link"))
      end
    end
  end

  # #393: best-effort SAR finding -> SSP statement linkage. Runs after
  # findings are created. When the SAR has a linked SSP and the finding's
  # target.target-id matches a known statement_id on that SSP's controls,
  # set ssp_control_statement_id on the finding.
  def link_findings_to_ssp_statements
    ssp_id = @document.ssp_document_id
    return if ssp_id.blank?

    statements_by_id = SspControlStatement
      .joins(:ssp_control)
      .where(ssp_controls: { ssp_document_id: ssp_id })
      .pluck(:statement_id, :id)
      .to_h

    return if statements_by_id.empty?

    @document.sar_results.each do |result|
      result.sar_findings.where(ssp_control_statement_id: nil).find_each do |finding|
        target_id = finding.target_data&.dig("target-id")
        next if target_id.blank?
        match_id = statements_by_id[target_id]
        finding.update_columns(ssp_control_statement_id: match_id) if match_id
      end
    end
  end

  def profile_catalog_json
    return nil if @document.profile_document_id.blank?
    ProfileDocument.find_by(id: @document.profile_document_id)&.resolved_catalog_json
  end

  # ── Helpers ────────────────────────────────────────────────────

  def extract_text(value)
    return nil if value.nil?
    return value if value.is_a?(String)
    value.to_s
  end

  def extract_facet(risk, name)
    return nil unless risk
    (risk["characterizations"] || []).each do |char|
      (char["facets"] || []).each do |facet|
        return facet["value"] if facet["name"] == name
      end
    end
    nil
  end

  def parse_datetime(value)
    return nil if value.blank?
    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end
end
