class PoamJsonParserService
  include BatchInsertable

  def initialize(poam_document, file_path)
    @document  = poam_document
    @file_path = file_path
  end

  def parse
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)

    poam = data["plan-of-action-and-milestones"] || raise("Invalid OSCAL POA&M: missing 'plan-of-action-and-milestones' root key")

    metadata     = poam["metadata"] || {}
    observations = poam["observations"] || []
    risks        = poam["risks"] || []
    items        = poam["poam-items"] || []

    update_document_metadata(metadata, poam, observations, risks)

    risk_map        = build_risk_map(risks)
    observation_map = build_observation_map(observations)

    control_attrs = []
    field_entries = []

    items.each_with_index do |item, idx|
      related_risk_uuid = item.dig("related-risks", 0, "risk-uuid")
      related_obs_uuid  = item.dig("related-observations", 0, "observation-uuid")
      risk = risk_map[related_risk_uuid]

      attrs = {
        title:                    item["title"],
        description:              extract_text(item["description"]),
        poam_item_uuid:           item["uuid"],
        risk_status:              risk&.dig("status"),
        risk_level:               extract_impact(risk),
        likelihood:               extract_facet(risk, "likelihood"),
        impact:                   extract_facet(risk, "impact"),
        deadline:                 parse_date(risk&.dig("deadline")),
        related_risk_uuid:        related_risk_uuid,
        related_observation_uuid: related_obs_uuid,
        row_order:                idx
      }

      ctrl_idx = control_attrs.size
      control_attrs << attrs

      # Store risk details as fields
      if risk
        field_entries << [ ctrl_idx, "risk_title", risk["title"] ] if risk["title"].present?
        field_entries << [ ctrl_idx, "risk_statement", extract_text(risk["statement"]) ] if risk["statement"].present?

        # Mitigating factors
        factors = (risk["mitigating-factors"] || []).map { |mf| extract_text(mf["description"]) }.compact.join("\n\n")
        field_entries << [ ctrl_idx, "mitigating_factors", factors ] if factors.present?

        # Remediations
        (risk["remediations"] || []).each_with_index do |rem, _ri|
          field_entries << [ ctrl_idx, "remediation_lifecycle", rem["lifecycle"] ] if rem["lifecycle"].present?
          field_entries << [ ctrl_idx, "remediation_title", rem["title"] ] if rem["title"].present?
          field_entries << [ ctrl_idx, "remediation_description", extract_text(rem["description"]) ] if rem["description"].present?

          # Milestones
          (rem["tasks"] || []).each do |task|
            next unless task["type"] == "milestone"
            field_entries << [ ctrl_idx, "milestone_title", task["title"] ] if task["title"].present?
            timing = task.dig("timing", "within-date-range")
            if timing
              range = [ timing["start"], timing["end"] ].compact.join(" → ")
              field_entries << [ ctrl_idx, "milestone_date", range ] if range.present?
            end
          end
        end
      end

      # Store observation details as fields
      obs = observation_map[related_obs_uuid]
      if obs
        field_entries << [ ctrl_idx, "observation_title", obs["title"] ] if obs["title"].present?
        field_entries << [ ctrl_idx, "observation_description", extract_text(obs["description"]) ] if obs["description"].present?
      end
    end

    batch_insert_records(
      control_class: PoamItem,
      field_class:   PoamItemField,
      document_fk:   :poam_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  private

  def update_document_metadata(metadata, poam, observations, risks)
    import_ssp   = poam["import-ssp"]
    system_id    = poam["system-id"]
    back_matter  = poam.dig("back-matter", "resources") || []

    @document.update!(
      poam_version:     metadata["version"],
      oscal_version:    metadata["oscal-version"],
      system_id:        system_id.is_a?(Hash) ? system_id["id"] : system_id&.to_s,
      observations_data: observations,
      risks_data:       risks,
      import_metadata:  {
        "uuid"        => poam["uuid"],
        "import_ssp"  => import_ssp,
        "back_matter" => back_matter
      }.compact
    )
  end

  def build_risk_map(risks)
    risks.each_with_object({}) do |risk, map|
      map[risk["uuid"]] = risk if risk["uuid"]
    end
  end

  def build_observation_map(observations)
    observations.each_with_object({}) do |obs, map|
      map[obs["uuid"]] = obs if obs["uuid"]
    end
  end

  def extract_text(value)
    return nil if value.nil?
    return value if value.is_a?(String)
    # OSCAL prose can be a string or a hash with paragraphs
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

  def extract_impact(risk)
    extract_facet(risk, "impact")
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value)
  rescue Date::Error
    nil
  end
end
