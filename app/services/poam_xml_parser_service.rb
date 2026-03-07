class PoamXmlParserService
  include BatchInsertable

  OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0"

  def initialize(poam_document, file_path)
    @document  = poam_document
    @file_path = file_path
  end

  def parse
    xml  = File.read(@file_path).force_encoding("UTF-8")
    doc  = Nokogiri::XML(xml) { |config| config.noblanks }
    root = doc.at_xpath("//xmlns:plan-of-action-and-milestones", "xmlns" => OSCAL_NS) ||
           doc.root

    raise "Invalid OSCAL POA&M XML" unless root

    metadata     = root.at_xpath("xmlns:metadata", "xmlns" => OSCAL_NS)
    observations = root.xpath("xmlns:observation", "xmlns" => OSCAL_NS)
    risks        = root.xpath("xmlns:risk", "xmlns" => OSCAL_NS)
    items        = root.xpath("xmlns:poam-item", "xmlns" => OSCAL_NS)

    observations_json = observations.map { |o| observation_to_hash(o) }
    risks_json        = risks.map { |r| risk_to_hash(r) }

    update_document_metadata(metadata, root, observations_json, risks_json)

    risk_map        = risks_json.index_by { |r| r["uuid"] }
    observation_map = observations_json.index_by { |o| o["uuid"] }

    control_attrs = []
    field_entries = []

    items.each_with_index do |item, idx|
      related_risk_uuid = item.at_xpath("xmlns:associated-risk", "xmlns" => OSCAL_NS)&.[]("risk-uuid")
      related_obs_uuid  = item.at_xpath("xmlns:related-observation", "xmlns" => OSCAL_NS)&.[]("observation-uuid")
      risk = risk_map[related_risk_uuid]

      attrs = {
        title:                    text(item, "title"),
        description:              text(item, "description"),
        poam_item_uuid:           item["uuid"],
        risk_status:              risk&.dig("status"),
        risk_level:               extract_facet(risk, "impact"),
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
        field_entries << [ ctrl_idx, "risk_statement", risk["statement"] ] if risk["statement"].present?

        factors = (risk["mitigating-factors"] || []).map { |mf| mf["description"] }.compact.join("\n\n")
        field_entries << [ ctrl_idx, "mitigating_factors", factors ] if factors.present?

        (risk["remediations"] || []).each do |rem|
          field_entries << [ ctrl_idx, "remediation_lifecycle", rem["lifecycle"] ] if rem["lifecycle"].present?
          field_entries << [ ctrl_idx, "remediation_title", rem["title"] ] if rem["title"].present?
          field_entries << [ ctrl_idx, "remediation_description", rem["description"] ] if rem["description"].present?

          (rem["tasks"] || []).each do |task|
            next unless task["type"] == "milestone"
            field_entries << [ ctrl_idx, "milestone_title", task["title"] ] if task["title"].present?
            if task["start"] || task["end"]
              range = [ task["start"], task["end"] ].compact.join(" → ")
              field_entries << [ ctrl_idx, "milestone_date", range ] if range.present?
            end
          end
        end
      end

      # Store observation details as fields
      obs = observation_map[related_obs_uuid]
      if obs
        field_entries << [ ctrl_idx, "observation_title", obs["title"] ] if obs["title"].present?
        field_entries << [ ctrl_idx, "observation_description", obs["description"] ] if obs["description"].present?
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

  def update_document_metadata(metadata, root, observations_json, risks_json)
    import_ssp = root.at_xpath("xmlns:import-ssp", "xmlns" => OSCAL_NS)
    sys_id     = root.at_xpath("xmlns:system-id", "xmlns" => OSCAL_NS)
    back_matter_resources = root.xpath("xmlns:back-matter/xmlns:resource", "xmlns" => OSCAL_NS)

    @document.update!(
      poam_version:     text(metadata, "version"),
      oscal_version:    text(metadata, "oscal-version"),
      system_id:        sys_id&.text&.strip,
      observations_data: observations_json,
      risks_data:       risks_json,
      import_metadata:  {
        "uuid"        => root["uuid"],
        "import_ssp"  => import_ssp ? { "href" => import_ssp["href"] } : nil,
        "back_matter" => back_matter_resources.map { |r| { "uuid" => r["uuid"], "title" => text(r, "title") } }
      }.compact
    )
  end

  def observation_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "methods"     => node.xpath("xmlns:method", "xmlns" => OSCAL_NS).map(&:text),
      "types"       => node.xpath("xmlns:type", "xmlns" => OSCAL_NS).map(&:text),
      "collected"   => text(node, "collected"),
      "expires"     => text(node, "expires"),
      "remarks"     => text(node, "remarks"),
      "subjects"    => node.xpath("xmlns:subject", "xmlns" => OSCAL_NS).map { |s|
        { "subject-uuid" => s["subject-uuid"], "type" => s["type"] }
      }
    }.compact
  end

  def risk_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "statement"   => text(node, "statement"),
      "status"      => text(node, "status"),
      "deadline"    => text(node, "deadline"),
      "characterizations" => node.xpath("xmlns:characterization", "xmlns" => OSCAL_NS).map { |c|
        {
          "origin" => {
            "actors" => c.xpath("xmlns:origin/xmlns:actor", "xmlns" => OSCAL_NS).map { |a|
              { "type" => a["type"], "actor-uuid" => a["actor-uuid"] }
            }
          },
          "facets" => c.xpath("xmlns:facet", "xmlns" => OSCAL_NS).map { |f|
            { "name" => f["name"], "value" => f["value"], "system" => f["system"] }
          }
        }
      },
      "mitigating-factors" => node.xpath("xmlns:mitigating-factor", "xmlns" => OSCAL_NS).map { |mf|
        { "uuid" => mf["uuid"], "description" => text(mf, "description") }
      },
      "remediations" => node.xpath("xmlns:response", "xmlns" => OSCAL_NS).map { |r|
        {
          "uuid"        => r["uuid"],
          "lifecycle"   => r["lifecycle"],
          "title"       => text(r, "title"),
          "description" => text(r, "description"),
          "props"       => r.xpath("xmlns:prop", "xmlns" => OSCAL_NS).map { |p| { "name" => p["name"], "value" => p["value"] } },
          "tasks"       => r.xpath("xmlns:task", "xmlns" => OSCAL_NS).map { |t|
            timing = t.at_xpath("xmlns:timing/xmlns:within-date-range", "xmlns" => OSCAL_NS)
            {
              "uuid"  => t["uuid"],
              "type"  => t["type"],
              "title" => text(t, "title"),
              "description" => text(t, "description"),
              "start" => timing&.[]("start"),
              "end"   => timing&.[]("end")
            }.compact
          }
        }
      },
      "related-observations" => node.xpath("xmlns:related-observation", "xmlns" => OSCAL_NS).map { |ro|
        { "observation-uuid" => ro["observation-uuid"] }
      }
    }.compact
  end

  def text(node, child_name)
    return nil unless node
    child = node.at_xpath("xmlns:#{child_name}", "xmlns" => OSCAL_NS)
    child&.text&.strip&.presence
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

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value)
  rescue Date::Error
    nil
  end
end
