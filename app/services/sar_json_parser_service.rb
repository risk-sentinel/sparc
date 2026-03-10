# Parses an OSCAL Assessment Results JSON file into the relational SAR model.
#
# Usage:
#   SarJsonParserService.new(sar_document, file_path).parse
#   # or from an already-parsed hash (used by XML parser delegation):
#   SarJsonParserService.new(sar_document, nil).parse_from_hash(data)
#
class SarJsonParserService
  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)
    parse_from_hash(data)
  end

  def parse_from_hash(data)
    ar = data["assessment-results"] || raise("Invalid OSCAL Assessment Results: missing 'assessment-results' root key")

    ActiveRecord::Base.transaction do
      update_document_metadata(ar)
      @document.assign_oscal_uuid!(ar["uuid"])
      parse_local_definitions(ar["local-definitions"])
      parse_results(ar["results"] || [])
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

      record = sar_result.sar_findings.create!(
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
