# Parses an OSCAL SSP JSON file into the relational SSP model.
#
# Usage:
#   SspJsonParserService.new(ssp_document, file_path).parse
#   # or from an already-parsed hash (used by XML parser delegation):
#   SspJsonParserService.new(ssp_document, nil).parse_from_hash(data)
#
class SspJsonParserService
  include ProgressTrackable
  include BackMatterPromotable

  # OSCAL keys / repeated messages reused across the JSON walk.
  IMPLEMENTATION_STATUS    = "implementation-status".freeze
  RESPONSIBLE_ROLES        = "responsible-roles".freeze
  BY_COMPONENTS            = "by-components".freeze
  DATE_AUTHORIZED          = "date-authorized".freeze
  SECURITY_IMPACT_LEVEL    = "security-impact-level".freeze
  CONFIDENTIALITY_IMPACT   = "confidentiality-impact".freeze
  INTEGRITY_IMPACT         = "integrity-impact".freeze
  AVAILABILITY_IMPACT      = "availability-impact".freeze
  ADJUSTMENT_JUSTIFICATION = "adjustment-justification".freeze
  NO_DESCRIPTION           = "No description provided.".freeze

  # Statements the import could not create, with the reason (#963). Kept so a
  # caller can report a partial import as partial: previously these went only
  # to the log, and an import that dropped rows still looked like a clean one.
  attr_reader :skipped_statements

  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
    @skipped_statements = []
  end

  def parse
    update_processing_stage!(:reading_file)
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)
    parse_from_hash(data)
  end

  def parse_from_hash(data)
    ssp = data["system-security-plan"] || raise(DocumentParseError, "Invalid OSCAL SSP: missing 'system-security-plan' root key")

    update_processing_stage!(:creating_records)
    ActiveRecord::Base.transaction do
      update_document_metadata(ssp)
      @document.assign_oscal_uuid!(ssp["uuid"])
      parse_system_characteristics(ssp["system-characteristics"])
      @component_map = parse_system_implementation(ssp["system-implementation"])
      parse_control_implementation(ssp["control-implementation"], @component_map)
      link_inheritances!
    end
  end

  private

  # ── Document-level metadata ──────────────────────────────────────

  def update_document_metadata(ssp)
    metadata = ssp["metadata"] || {}
    profile_href = ssp.dig("import-profile", "href")

    # #395 P2: resolve `uuid:<...>` import-profile.href to a ProfileDocument
    # and persist the FK (raw href column is still preserved for round-trip).
    profile_id = OscalMetadata.resolve_import_href(profile_href, ProfileDocument)&.id

    attrs = {
      creation_method:    "oscal_import",
      oscal_version:      metadata["oscal-version"],
      ssp_version:        metadata["version"],
      import_profile_href: profile_href,
      metadata_extra:     metadata.except("title", "version", "oscal-version", "last-modified"),
      import_metadata:    {
        "uuid" => ssp["uuid"]
      }.compact
    }
    attrs[:profile_document_id] = profile_id if profile_id

    @document.update!(**attrs)
    @document.update!(name: metadata["title"]) if metadata["title"].present?

    # #583 — promote OSCAL back-matter to first-class BackMatterResource rows.
    promote_back_matter_resources(ssp.dig("back-matter", "resources"))
  end

  # ── System characteristics ───────────────────────────────────────

  def parse_system_characteristics(sc)
    return unless sc

    @document.update!(
      system_id:                          sc.dig("system-ids", 0, "id"),
      description:                        extract_text(sc["description"]),
      system_name_short:                  sc["system-name-short"],
      security_sensitivity_level:         sc["security-sensitivity-level"],
      system_status:                      sc.dig("status", "state") || "operational",
      date_authorized:                    sc[DATE_AUTHORIZED],
      authorization_boundary_description: extract_text(sc.dig("authorization-boundary", "description")),
      network_architecture_description:   extract_text(sc.dig("network-architecture", "description")),
      data_flow_description:              extract_text(sc.dig("data-flow", "description")),
      security_objective_confidentiality: sc.dig(SECURITY_IMPACT_LEVEL, "security-objective-confidentiality"),
      security_objective_integrity:       sc.dig(SECURITY_IMPACT_LEVEL, "security-objective-integrity"),
      security_objective_availability:    sc.dig(SECURITY_IMPACT_LEVEL, "security-objective-availability")
    )

    # Update name from system-name if present
    @document.update!(name: sc["system-name"]) if sc["system-name"].present? && @document.name.blank?

    parse_information_types(sc.dig("system-information", "information-types") || [])
  end

  def parse_information_types(types)
    types.each do |it|
      @document.ssp_information_types.create!(
        uuid:                              it["uuid"] || SecureRandom.uuid,
        title:                             it["title"] || "Information Type",
        description:                       extract_text(it["description"]) || NO_DESCRIPTION,
        confidentiality_impact_base:       it.dig(CONFIDENTIALITY_IMPACT, "base"),
        confidentiality_impact_selected:   it.dig(CONFIDENTIALITY_IMPACT, "selected"),
        confidentiality_impact_adjustment: it.dig(CONFIDENTIALITY_IMPACT, ADJUSTMENT_JUSTIFICATION),
        integrity_impact_base:             it.dig(INTEGRITY_IMPACT, "base"),
        integrity_impact_selected:         it.dig(INTEGRITY_IMPACT, "selected"),
        integrity_impact_adjustment:       it.dig(INTEGRITY_IMPACT, ADJUSTMENT_JUSTIFICATION),
        availability_impact_base:          it.dig(AVAILABILITY_IMPACT, "base"),
        availability_impact_selected:      it.dig(AVAILABILITY_IMPACT, "selected"),
        availability_impact_adjustment:    it.dig(AVAILABILITY_IMPACT, ADJUSTMENT_JUSTIFICATION),
        categorizations_data:              it["categorizations"] || [],
        props_data:                        it["props"] || [],
        links_data:                        it["links"] || []
      )
    end
  end

  # ── System implementation ────────────────────────────────────────

  def parse_system_implementation(si)
    return {} unless si

    component_map = {}
    parse_components(si["components"] || [], component_map)
    parse_users(si["users"] || [])
    parse_leveraged_authorizations(si["leveraged-authorizations"] || [])
    parse_inventory_items(si["inventory-items"] || [])
    component_map
  end

  def parse_components(components, component_map)
    components.each do |comp|
      status = comp["status"] || {}
      record = @document.ssp_components.create!(
        uuid:                   comp["uuid"],
        component_type:         comp["type"],
        title:                  comp["title"] || "Untitled Component",
        description:            extract_text(comp["description"]) || NO_DESCRIPTION,
        purpose:                comp["purpose"],
        status_state:           status["state"] || "operational",
        status_remarks:         status["remarks"],
        responsible_roles_data: comp[RESPONSIBLE_ROLES] || [],
        protocols_data:         comp["protocols"] || [],
        props_data:             comp["props"] || [],
        links_data:             comp["links"] || [],
        remarks:                comp["remarks"]
      )
      component_map[comp["uuid"]] = record
    end
  end

  def parse_users(users)
    users.each do |user|
      @document.ssp_users.create!(
        uuid:                       user["uuid"] || SecureRandom.uuid,
        title:                      user["title"],
        description:                user["description"],
        short_name:                 user["short-name"],
        role_ids_data:              user["role-ids"] || [],
        authorized_privileges_data: user["authorized-privileges"] || [],
        props_data:                 user["props"] || [],
        links_data:                 user["links"] || [],
        remarks:                    user["remarks"]
      )
    end
  end

  def parse_leveraged_authorizations(auths)
    auths.each do |auth|
      # Legacy: keep the per-SSP record so anything reading from
      # `ssp_leveraged_authorizations` still works. The new #396 flow
      # layers a boundary-level `LeveragedAuthorization` on top.
      @document.ssp_leveraged_authorizations.create!(
        uuid:            auth["uuid"] || SecureRandom.uuid,
        title:           auth["title"],
        party_uuid:      auth["party-uuid"],
        date_authorized: auth[DATE_AUTHORIZED],
        props_data:      auth["props"] || [],
        links_data:      auth["links"] || [],
        remarks:         auth["remarks"]
      )

      upsert_leveraged_authorization_record(auth)
    end
  end

  # #396: create/find a LeveragedAuthorization on the leveraging boundary.
  # Attempts to resolve the leveraged boundary via `link[rel="leveraged-system"]`
  # href (uuid:<boundary.uuid> or uuid:<ssp.uuid>). Falls back to a
  # Scenario-2/3 record when the leveraged system isn't in SPARC.
  def upsert_leveraged_authorization_record(auth)
    leveraging_boundary = @document.authorization_boundary
    return unless leveraging_boundary

    leveraged_boundary = resolve_leveraged_boundary(auth["links"] || [])
    crm_type = leveraged_boundary ? "oscal_with_access" : "oscal_no_access"

    la = LeveragedAuthorization.find_or_initialize_by(
      leveraging_boundary_id: leveraging_boundary.id,
      leveraged_boundary_id: leveraged_boundary&.id
    )
    # `leveraged_authorizations.uuid` is unique GLOBALLY, but this record is
    # keyed on the (leveraging, leveraged) pair — so importing the same OSCAL
    # SSP into two different boundaries produced two rows carrying the same
    # imported uuid and raised RecordNotUnique, aborting the whole import.
    #
    # Exposed by #952: this method opens with `return unless leveraging_boundary`
    # and simply never ran while documents could have no boundary.
    #
    # The imported uuid is kept when it is free, which is the round-trip-stable
    # case (#957). When it is already taken, the two leveraged authorizations
    # are genuinely different subjects in different SSPs and need distinct
    # identifiers, so a fresh one is minted.
    la.uuid ||= claimable_leveraged_authorization_uuid(auth["uuid"])
    la.name              = auth["title"] || la.name.presence || "Leveraged System"
    # For new records, the DB default ("oscal_with_access") means
    # `crm_type.presence` is never nil — explicitly pick based on href
    # resolution. For existing records, keep whatever the user configured.
    la.crm_type          = crm_type if la.new_record?
    la.date_authorized ||= parse_date(auth[DATE_AUTHORIZED])
    la.description     ||= extract_text(auth["remarks"])
    la.metadata        = (la.metadata || {}).merge(
      "party_uuid" => auth["party-uuid"],
      "raw_links"  => auth["links"] || [],
      "raw_props"  => auth["props"] || []
    )
    la.save!
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    # A leveraged-authorization row that cannot be written must not take the
    # rest of the import down with it — the same rule #963 established for
    # colliding statements.
    Rails.logger.warn("[SspJsonParser] leveraged_authorization upsert failed: #{e.message}")
  end

  # The imported uuid when nothing else holds it, otherwise a fresh one.
  def claimable_leveraged_authorization_uuid(imported_uuid)
    return SecureRandom.uuid if imported_uuid.blank?
    return imported_uuid unless LeveragedAuthorization.exists?(uuid: imported_uuid)

    SecureRandom.uuid
  end

  def resolve_leveraged_boundary(links)
    links.each do |link|
      next unless link.is_a?(Hash)
      href = link["href"]
      next if href.blank?

      if (ssp = OscalMetadata.resolve_import_href(href, SspDocument))
        return ssp.authorization_boundary
      end
      if (b = OscalMetadata.resolve_import_href(href, AuthorizationBoundary))
        return b
      end
    end
    nil
  end

  def parse_date(value)
    return nil if value.blank?
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_inventory_items(items)
    items.each do |item|
      @document.ssp_inventory_items.create!(
        uuid:                       item["uuid"] || SecureRandom.uuid,
        description:                extract_text(item["description"]) || NO_DESCRIPTION,
        implemented_components_data: item["implemented-components"] || [],
        responsible_parties_data:    item["responsible-parties"] || [],
        props_data:                  item["props"] || [],
        links_data:                  item["links"] || [],
        remarks:                     item["remarks"]
      )
    end
  end

  # ── Control implementation ───────────────────────────────────────

  def parse_control_implementation(ci, component_map)
    return unless ci

    (ci["implemented-requirements"] || []).each_with_index do |ir, idx|
      ctrl = @document.ssp_controls.create!(
        control_id: ir["control-id"],
        row_order:  idx
      )

      parse_implemented_requirement_props(ctrl, ir)
      parse_by_components(ctrl, ir[BY_COMPONENTS] || [], component_map)
      parse_statements_as_fields(ctrl, ir)
      parse_remarks_as_field(ctrl, ir)
    end
  end

  # #946 — the inverse of the exporter's status token.
  #
  # `OscalSspExportService#build_props` writes the OSCAL `implementation-status`
  # as `status.downcase.gsub(/\s+/, "-")`, so "Implemented" leaves as
  # "implemented" and "Not Applicable" as "not-applicable". Storing that back
  # verbatim put a value in the field that is not one of
  # `SspControlField::VALID_STATUSES`, and everything that counts compliance
  # matches the canonical spelling — so a re-imported SSP reported **0.0%
  # compliant with 21 controls implemented**, which reads as a wall of findings
  # that are not real.
  #
  # Derived FROM `VALID_STATUSES` rather than typed out, so the two cannot
  # drift: whatever the exporter can emit, this maps back.
  STATUS_FROM_OSCAL = SspControlField::VALID_STATUSES
                        .index_by { |status| status.downcase.gsub(/\s+/, "-") }
                        .freeze

  # A vocabulary another tool used that SPARC has no equivalent for is left
  # exactly as it arrived. OSCAL also defines `planned`, `partial` and
  # `alternative`; mapping those onto SPARC's four would be inventing an
  # assessment judgement nobody made, and a value that is visibly foreign is
  # better than one that is silently wrong.
  def canonical_status(value)
    STATUS_FROM_OSCAL[value.to_s.downcase] || value
  end

  def parse_implemented_requirement_props(ctrl, ir)
    (ir["props"] || []).each do |prop|
      field_name = prop_name_to_field(prop["name"])
      next unless field_name

      value = field_name == "status" ? canonical_status(prop["value"]) : prop["value"]

      ctrl.ssp_control_fields.create!(
        field_name:  field_name,
        field_value: value
      )
    end
  end

  def parse_by_components(ctrl, by_components, component_map)
    by_components.each do |bc|
      component = component_map[bc["component-uuid"]]
      next unless component

      ctrl.ssp_by_components.create!(
        ssp_component:         component,
        uuid:                  bc["uuid"] || SecureRandom.uuid,
        description:           extract_text(bc["description"]),
        implementation_status: bc.dig(IMPLEMENTATION_STATUS, "state") || bc[IMPLEMENTATION_STATUS],
        export_data:           bc["export"] || {},
        inherited_data:        bc["inherited"] || [],
        satisfied_data:        bc["satisfied"] || [],
        responsible_roles_data: bc[RESPONSIBLE_ROLES] || [],
        set_parameters_data:   bc["set-parameters"] || [],
        props_data:            bc["props"] || [],
        links_data:            bc["links"] || [],
        remarks:               bc["remarks"]
      )
    end
  end

  # #393: statements are now first-class records on ssp_control_statements.
  # Preserve the OSCAL statement UUID when supplied; fall back to the
  # deterministic OscalUuidService.derived value (matches what the
  # exporter emits for backfilled rows so re-export is UUID-stable).
  # #946 — the inverse of OscalSspExportService#build_statements_from_fields.
  #
  # That exporter synthesises an OSCAL statement from a control FIELD, naming it
  # `<control>_priv` (implementation_statement) or `<control>_pub`
  # (implementation_summary). Re-importing those as statement ROWS would be a
  # lossy round-trip in a way that is invisible until someone opens the screen:
  # the narrative would survive in the database but the edit form, which renders
  # the field, would show every control as blank.
  #
  # Restoring the field is what makes export -> import faithful. A statement
  # SPARC synthesised from a field is not independent content, so it goes back
  # where it came from rather than becoming a second copy.
  SYNTHESISED_STATEMENT_FIELDS = {
    "_priv" => "implementation_statement",
    "_pub"  => "implementation_summary"
  }.freeze

  def synthesised_statement_field(stmt_id)
    suffix = SYNTHESISED_STATEMENT_FIELDS.keys.find { |s| stmt_id.to_s.end_with?(s) }
    suffix && SYNTHESISED_STATEMENT_FIELDS[suffix]
  end

  def parse_statements_as_fields(ctrl, ir)
    (ir["statements"] || []).each_with_index do |stmt, idx|
      stmt_id = stmt["statement-id"]
      next if stmt_id.blank?

      narrative = stmt["remarks"] || stmt.dig(BY_COMPONENTS, 0, "description")

      if (field_name = synthesised_statement_field(stmt_id))
        if narrative.present?
          ctrl.ssp_control_fields.create!(field_name: field_name, field_value: narrative)
        end
        next
      end
      uuid = stmt["uuid"].presence ||
             OscalUuidService.derived(ctrl.uuid, "ssp-statement", stmt_id)

      # #396: annotate the statement as a `provided`/`responsibility`
      # marker when by-components[].satisfied[] or .responsibilities[]
      # are present. The tag lets LeveragedAuthorization#inheritable_statements
      # query-match on set_parameters_data.
      set_params = statement_set_parameters(stmt)

      # #963 — the create runs in its OWN savepoint. Rescuing a uniqueness
      # violation without one does not skip the row, it kills the import:
      # Postgres aborts the whole transaction on the failed statement, and
      # every statement after it raises InFailedSqlTransaction until the
      # outer transaction rolls back. The rescue below was written to make one
      # bad statement survivable and, without `requires_new`, did the opposite.
      #
      # This is reachable on ordinary input, not just malformed input:
      # `idx_ssp_stmt_on_uuid` is unique GLOBALLY, and an export carries the
      # statement UUIDs it already has, so re-importing a document the instance
      # already holds collides on the first statement.
      record = ActiveRecord::Base.transaction(requires_new: true) do
        ctrl.ssp_control_statements.create!(
          uuid:                   uuid,
          statement_id:           stmt_id,
          implementation_prose:   narrative,
          remarks:                stmt["remarks"],
          responsible_roles_data: stmt[RESPONSIBLE_ROLES] || [],
          set_parameters_data:    set_params,
          row_order:              idx
        )
      end

      # #396 + #398: resolve inheritance links from statements[].links[]
      # with rel="implements" (CDEF source) or rel="inherited" (leveraged
      # SSP source). The href carries the source UUID; we defer actual
      # source-record resolution to a second pass in `link_inheritances!`
      # because the source may be imported later in the same run.
      queue_inheritance_links(record, stmt)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      # Counted, not only logged: an import that silently drops statements
      # reports success while delivering less than it was given.
      @skipped_statements << { statement_id: stmt_id, error: e.message }
      Rails.logger.warn("[SspJsonParser] skipping statement #{stmt_id}: #{e.message}")
    end
  end

  # #396: tag set-parameters with provided/responsibility markers when the
  # statement's by-components carry satisfied[]/responsibilities[]. Extracted
  # from #parse_statements_as_fields to bound its cognitive complexity.
  # #958 — OSCAL models both `provided` and `responsibilities` under
  # `by-component.export`, which is where SPARC's own exporter now writes
  # them. The older shapes (`satisfied` / `responsibilities` directly on the
  # by-component) are still read so documents imported before that fix, and
  # any producer using them, keep working — but `export` is the conformant
  # one, and without it a SPARC export could not be re-imported as what it
  # was.
  def statement_set_parameters(stmt)
    set_params = Array(stmt["set-parameters"]).dup

    (stmt[BY_COMPONENTS] || []).each do |bc|
      exported = bc["export"].is_a?(Hash) ? bc["export"] : {}

      provided = Array(exported["provided"]).any? || Array(bc["satisfied"]).any?
      responsibility = Array(exported["responsibilities"]).any? || Array(bc["responsibilities"]).any?

      set_params << { "tag" => "provided" } if provided && no_marker?(set_params, "provided")
      set_params << { "tag" => "responsibility" } if responsibility && no_marker?(set_params, "responsibility")
    end

    set_params
  end

  def no_marker?(set_params, tag)
    set_params.none? { |p| p.is_a?(Hash) && p["tag"] == tag }
  end

  # #396 + #398: queue inheritance links from statements[].links[] for the
  # second-pass resolution in #link_inheritances!.
  def queue_inheritance_links(record, stmt)
    @pending_inheritance_links ||= []
    Array(stmt["links"]).each do |link|
      next unless link.is_a?(Hash)
      rel = link["rel"]
      next unless %w[implements inherited].include?(rel)
      href = link["href"].to_s
      source_uuid = extract_uuid(href)
      next if source_uuid.blank?

      @pending_inheritance_links << {
        target_id: record.id,
        source_uuid: source_uuid,
        rel: rel
      }
    end
  end

  # Second-pass resolution of pending inheritance links. Called at the end
  # of parse_control_implementation so all statements exist before we try
  # to link them.
  def link_inheritances!
    return unless @pending_inheritance_links

    @pending_inheritance_links.each do |entry|
      source, source_type = resolve_inheritance_source(entry[:source_uuid], entry[:rel])
      next unless source

      # #963 — same savepoint requirement as the statement create above.
      # `find_or_create_by!` races and collides like any other insert, and
      # rescuing that without `requires_new` would poison the transaction and
      # take down the rest of the link pass.
      ActiveRecord::Base.transaction(requires_new: true) do
        SspControlStatementInheritance.find_or_create_by!(
          ssp_control_statement_id: entry[:target_id],
          source_type: source_type,
          source_id: source.id
        ) do |link|
          link.source_uuid = entry[:source_uuid]
        end
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[SspJsonParser] inheritance link skipped: #{e.message}")
    end
  ensure
    @pending_inheritance_links = nil
  end

  def resolve_inheritance_source(source_uuid, rel)
    if rel == "implements"
      stmt = CdefControlStatement.find_by(uuid: source_uuid)
      [ stmt, "CdefControlStatement" ] if stmt
    else
      stmt = SspControlStatement.find_by(uuid: source_uuid)
      [ stmt, "SspControlStatement" ] if stmt
    end
  end

  def extract_uuid(href)
    return nil if href.blank?
    # Accept "uuid:<uuid>", "#<uuid>", or bare "<uuid>".
    href.to_s.sub(/\A(uuid:|#)/, "")
  end

  # #946 — the inverse of OscalSspExportService#build_remarks.
  #
  # That exporter packs FIVE distinct fields into one `remarks` string, each
  # behind a label ("Stated Requirement: …\n\nNotes: …"). Filing the whole
  # string under `notes` collapsed all five into one and put four of them in the
  # wrong place, so a re-imported SSP showed its catalog requirement as an
  # operator's note and lost the note itself.
  #
  # Anything that does not carry a recognised label is genuinely a remark and
  # still becomes `notes`, so remarks written by other tools survive.
  REMARK_LABEL_FIELDS = {
    "Stated Requirement"  => "stated_requirement",
    "Notes"               => "notes",
    "Expected Completion" => "expected_completion",
    "Inherited From"      => "inherited_from",
    "History"             => "history"
  }.freeze

  def parse_remarks_as_field(ctrl, ir)
    remarks = ir["remarks"]
    return if remarks.blank?

    labelled, unlabelled = split_labelled_remarks(remarks)

    labelled.each do |field_name, value|
      ctrl.ssp_control_fields.create!(field_name: field_name, field_value: value)
    end

    return if unlabelled.blank?

    ctrl.ssp_control_fields.create!(field_name: "notes", field_value: unlabelled)
  end

  # Returns [{field_name => value}, leftover_prose].
  def split_labelled_remarks(remarks)
    fields = {}
    leftovers = []

    remarks.to_s.split("\n\n").each do |part|
      label, value = part.split(": ", 2)
      field_name = REMARK_LABEL_FIELDS[label.to_s.strip]

      if field_name && value.present?
        fields[field_name] = value.strip
      else
        leftovers << part
      end
    end

    # `notes` may arrive both as a label and as unlabelled prose; the labelled
    # one is the one the exporter wrote, so it wins and the rest is appended.
    leftover = leftovers.join("\n\n").presence
    if leftover && fields["notes"]
      fields["notes"] = "#{fields['notes']}\n\n#{leftover}"
      leftover = nil
    end

    [ fields, leftover ]
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def prop_name_to_field(oscal_name)
    {
      IMPLEMENTATION_STATUS  => "status",
      "control-type"           => "control_application",
      "provided-as"            => "coverage_level",
      "control-origination"    => "control_type",
      "responsible-entities"   => "responsible_entities"
    }[oscal_name]
  end

  def extract_text(value)
    case value
    when String then value.presence
    when Hash   then value["value"].presence || value.to_s
    else value.to_s.presence
    end
  end
end
