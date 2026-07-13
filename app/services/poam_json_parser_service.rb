class PoamJsonParserService
  include ProgressTrackable
  include BackMatterPromotable

  # OSCAL element names reused across the JSON walk.
  OBSERVATION_UUID     = "observation-uuid".freeze
  RELATED_OBSERVATIONS = "related-observations".freeze
  RISK_UUID            = "risk-uuid".freeze

  def initialize(poam_document, file_path)
    @document  = poam_document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)
    parse_from_hash(data)
  end

  # Allows XML parser to delegate after converting XML→Hash
  def parse_from_hash(data)
    poam = data["plan-of-action-and-milestones"] || raise(DocumentParseError, "Invalid OSCAL POA&M: missing 'plan-of-action-and-milestones' root key")

    update_processing_stage!(:creating_records)
    ActiveRecord::Base.transaction do
      update_document_metadata(poam)
      @document.assign_oscal_uuid!(poam["uuid"])

      obs_map     = parse_observations(poam["observations"] || [])
      risk_map    = parse_risks(poam["risks"] || [], obs_map)
      finding_map = parse_findings(poam["findings"] || [], obs_map, risk_map)
      parse_local_definitions(poam["local-definitions"])
      parse_poam_items(poam["poam-items"] || [], risk_map, obs_map, finding_map)
    end
  end

  private

  # ── Document metadata ────────────────────────────────────────────

  def update_document_metadata(poam)
    metadata    = poam["metadata"] || {}
    import_ssp  = poam["import-ssp"]
    system_id   = poam["system-id"]

    # Preserve extra metadata fields for round-trip fidelity
    metadata_extra = metadata.except("title", "version", "oscal-version", "last-modified")

    # #395 P2: when import-ssp.href is `uuid:<...>`, resolve to an
    # SspDocument and persist the FK alongside the raw import_metadata
    # round-trip data.
    ssp_id = OscalMetadata
      .resolve_import_href(import_ssp.is_a?(Hash) ? import_ssp["href"] : nil, SspDocument)&.id

    attrs = {
      poam_version:            metadata["version"],
      oscal_version:           metadata["oscal-version"],
      system_id:               system_id.is_a?(Hash) ? system_id["id"] : system_id&.to_s,
      metadata_extra:          metadata_extra.presence || {},
      local_definitions_extra: {},
      import_metadata:         {
        "uuid"       => poam["uuid"],
        "import_ssp" => import_ssp
      }.compact
    }
    attrs[:ssp_document_id] = ssp_id if ssp_id

    @document.update!(**attrs)

    # #583 — promote OSCAL back-matter to first-class BackMatterResource rows.
    promote_back_matter_resources(poam.dig("back-matter", "resources"))
  end

  # ── Observations ─────────────────────────────────────────────────

  def parse_observations(observations)
    observations.each_with_object({}) do |obs, map|
      next unless obs["uuid"].present?

      record = @document.poam_observations.create!(
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

  # ── Risks ────────────────────────────────────────────────────────

  def parse_risks(risks, obs_map)
    risks.each_with_object({}) do |risk, map|
      next unless risk["uuid"].present?

      record = @document.poam_risks.create!(
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
        props_data:              risk["props"] || [],
        links_data:              risk["links"] || [],
        remarks:                 extract_text(risk["remarks"])
      )

      # Remediations (called "remediations" in JSON, maps to OSCAL "response")
      (risk["remediations"] || []).each_with_index do |rem, pos|
        parse_remediation(record, rem, pos)
      end

      # Related observations
      (risk[RELATED_OBSERVATIONS] || []).each do |ro|
        obs_record = obs_map[ro[OBSERVATION_UUID]]
        PoamRiskObservation.create!(poam_risk: record, poam_observation: obs_record) if obs_record
      end

      map[risk["uuid"]] = record
    end
  end

  def parse_remediation(risk_record, rem, position)
    remediation = risk_record.poam_remediations.create!(
      uuid:                 rem["uuid"] || SecureRandom.uuid,
      lifecycle:            rem["lifecycle"],
      title:                rem["title"],
      description:          extract_text(rem["description"]),
      origins_data:         rem["origins"] || [],
      required_assets_data: rem["required-assets"] || [],
      props_data:           rem["props"] || [],
      links_data:           rem["links"] || [],
      remarks:              extract_text(rem["remarks"]),
      position:             position
    )

    # Tasks/milestones
    (rem["tasks"] || []).each_with_index do |task, task_pos|
      parse_milestone(remediation, task, task_pos)
    end
  end

  def parse_milestone(remediation, task, position)
    timing   = task["timing"] || {}
    due_date = extract_due_date(timing)

    remediation.poam_milestones.create!(
      uuid:                   task["uuid"] || SecureRandom.uuid,
      milestone_type:         task["type"] || "milestone",
      title:                  task["title"],
      description:            extract_text(task["description"]),
      due_date:               due_date,
      timing_data:            timing,
      dependencies_data:      task["dependencies"] || [],
      responsible_roles_data: task["responsible-roles"] || [],
      subjects_data:          task["subjects"] || [],
      props_data:             task["props"] || [],
      links_data:             task["links"] || [],
      remarks:                extract_text(task["remarks"]),
      position:               position
    )
  end

  # ── Findings ─────────────────────────────────────────────────────

  def parse_findings(findings, obs_map, risk_map)
    findings.each_with_object({}) do |finding, map|
      next unless finding["uuid"].present?

      record = @document.poam_findings.create!(
        uuid:                          finding["uuid"],
        title:                         finding["title"],
        description:                   extract_text(finding["description"]),
        target_data:                   finding["target"] || {},
        implementation_statement_uuid: finding["implementation-statement-uuid"],
        origins_data:                  finding["origins"] || [],
        props_data:                    finding["props"] || [],
        links_data:                    finding["links"] || [],
        remarks:                       extract_text(finding["remarks"])
      )

      # Related observations
      (finding[RELATED_OBSERVATIONS] || []).each do |ro|
        obs_record = obs_map[ro[OBSERVATION_UUID]]
        PoamFindingObservation.create!(poam_finding: record, poam_observation: obs_record) if obs_record
      end

      # Related risks (accept both "related-risks" JSON and "associated-risks"
      # alias emitted by some XML→JSON converters).
      finding_risks = finding["related-risks"].presence || finding["associated-risks"] || []
      finding_risks.each do |rr|
        risk_record = risk_map[rr[RISK_UUID]]
        PoamFindingRisk.create!(poam_finding: record, poam_risk: risk_record) if risk_record
      end

      map[finding["uuid"]] = record
    end
  end

  # ── Local definitions ────────────────────────────────────────────

  def parse_local_definitions(local_defs)
    return if local_defs.blank?

    # Components
    (local_defs["components"] || []).each do |comp|
      comp_status = comp["status"] || {}
      @document.poam_local_components.create!(
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

    # Preserve other local-definitions data (inventory-items, assessment-assets, etc.)
    extra = local_defs.except("components")
    @document.update!(local_definitions_extra: extra) if extra.present?
  end

  # ── POA&M Items ──────────────────────────────────────────────────

  def parse_poam_items(items, risk_map, obs_map, finding_map)
    items.each_with_index do |item, idx|
      # OSCAL JSON spec calls this "related-risks" but the XML element is
      # <associated-risk>, so XML→JSON converters and some tools (e.g. the
      # Checkov→OSCAL pipeline) emit "associated-risks" in JSON. Accept both.
      item_risks = item["related-risks"].presence || item["associated-risks"] || []
      item_observations = item[RELATED_OBSERVATIONS] || []

      # Synthesize PoamRisk/PoamObservation records for inline references
      # whose UUIDs don't appear in the top-level risks/observations arrays.
      # Tools like Checkov often embed status/description directly in the
      # item-level reference instead of populating top-level risks[].
      item_risks.each { |rr| synthesize_risk_if_missing(rr, risk_map) }
      item_observations.each { |ro| synthesize_observation_if_missing(ro, obs_map) }

      # Determine primary risk for denormalization (now includes synthesized risks)
      primary_risk_uuid = item_risks.dig(0, RISK_UUID)
      primary_risk = risk_map[primary_risk_uuid]

      record = @document.poam_items.create!(
        title:          item["title"],
        description:    extract_text(item["description"]),
        poam_item_uuid: item["uuid"],
        risk_status:    primary_risk&.status,
        risk_level:     primary_risk&.impact,
        likelihood:     primary_risk&.likelihood,
        impact:         primary_risk&.impact,
        deadline:       primary_risk&.deadline,
        row_order:      idx,
        origins_data:   item["origins"] || [],
        props_data:     item["props"] || [],
        links_data:     item["links"] || [],
        remarks:        extract_text(item["remarks"])
      )

      # Join: item ↔ risks
      item_risks.each do |rr|
        risk_record = risk_map[rr[RISK_UUID]]
        PoamItemRisk.create!(poam_item: record, poam_risk: risk_record) if risk_record
      end

      # Join: item ↔ observations
      item_observations.each do |ro|
        obs_record = obs_map[ro[OBSERVATION_UUID]]
        PoamItemObservation.create!(poam_item: record, poam_observation: obs_record) if obs_record
      end

      # Join: item ↔ findings (if present)
      (item["related-findings"] || []).each do |rf|
        finding_record = finding_map[rf["finding-uuid"]]
        PoamItemFinding.create!(poam_item: record, poam_finding: finding_record) if finding_record
      end
    end
  end

  # Create a PoamRisk from inline reference data when the top-level risks
  # array doesn't contain a matching entry. Mutates risk_map in place.
  def synthesize_risk_if_missing(ref, risk_map)
    uuid = ref[RISK_UUID]
    return if uuid.blank? || risk_map.key?(uuid)
    return unless ref["status"].present? || ref["description"].present? || ref["title"].present?

    risk_map[uuid] = @document.poam_risks.create!(
      uuid:        uuid,
      title:       ref["title"].presence || "Risk #{uuid.first(8)}",
      description: extract_text(ref["description"]),
      status:      ref["status"]
    )
  end

  # Create a PoamObservation from inline reference data when the top-level
  # observations array doesn't contain a matching entry.
  def synthesize_observation_if_missing(ref, obs_map)
    uuid = ref[OBSERVATION_UUID]
    return if uuid.blank? || obs_map.key?(uuid)
    return unless ref["description"].present? || ref["title"].present?

    obs_map[uuid] = @document.poam_observations.create!(
      uuid:        uuid,
      title:       ref["title"].presence || "Observation #{uuid.first(8)}",
      description: extract_text(ref["description"])
    )
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def extract_text(value)
    return nil if value.nil?
    return value if value.is_a?(String)
    value.to_s
  end

  def extract_facet(risk, name)
    return nil unless risk
    Array(risk["characterizations"]).flat_map { |char| Array(char["facets"]) }
      .find { |facet| facet["name"] == name }&.[]("value")
  end

  def extract_due_date(timing)
    range = timing["within-date-range"]
    if range
      parse_date(range["end"] || range["start"])
    elsif timing["on-date"]
      parse_date(timing["on-date"]["date"])
    end
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value)
  rescue Date::Error
    nil
  end

  def parse_datetime(value)
    return nil if value.blank?
    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end
end
