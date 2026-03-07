class PoamXmlParserService
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

    # Convert XML nodes to intermediate hashes, then use same creation logic as JSON parser
    observations_json = root.xpath("xmlns:observation", "xmlns" => OSCAL_NS).map { |o| observation_to_hash(o) }
    risks_json        = root.xpath("xmlns:risk", "xmlns" => OSCAL_NS).map { |r| risk_to_hash(r) }
    findings_json     = root.xpath("xmlns:finding", "xmlns" => OSCAL_NS).map { |f| finding_to_hash(f) }
    items_json        = root.xpath("xmlns:poam-item", "xmlns" => OSCAL_NS).map { |i| poam_item_to_hash(i) }
    local_defs        = local_definitions_to_hash(root.at_xpath("xmlns:local-definitions", "xmlns" => OSCAL_NS))

    # Build a synthetic JSON-like structure and delegate to the JSON parser logic
    poam_hash = {
      "uuid"             => root["uuid"],
      "metadata"         => metadata_to_hash(root.at_xpath("xmlns:metadata", "xmlns" => OSCAL_NS)),
      "import-ssp"       => import_ssp_to_hash(root.at_xpath("xmlns:import-ssp", "xmlns" => OSCAL_NS)),
      "system-id"        => system_id_to_hash(root.at_xpath("xmlns:system-id", "xmlns" => OSCAL_NS)),
      "observations"     => observations_json,
      "risks"            => risks_json,
      "findings"         => findings_json,
      "local-definitions" => local_defs,
      "poam-items"       => items_json,
      "back-matter"      => back_matter_to_hash(root.at_xpath("xmlns:back-matter", "xmlns" => OSCAL_NS))
    }.compact

    # Wrap in expected structure and parse via JSON parser
    data = { "plan-of-action-and-milestones" => poam_hash }
    json_parser = PoamJsonParserService.new(@document, nil)
    json_parser.parse_from_hash(data)
  end

  private

  # ── XML → Hash converters ───────────────────────────────────────

  def metadata_to_hash(node)
    return {} unless node
    {
      "title"         => text(node, "title"),
      "version"       => text(node, "version"),
      "oscal-version" => text(node, "oscal-version"),
      "last-modified" => text(node, "last-modified"),
      "revisions"     => node.xpath("xmlns:revisions/xmlns:revision", "xmlns" => OSCAL_NS).map { |r|
        {
          "title"         => text(r, "title"),
          "version"       => text(r, "version"),
          "oscal-version" => text(r, "oscal-version"),
          "last-modified" => text(r, "last-modified")
        }.compact
      }.presence
    }.compact
  end

  def import_ssp_to_hash(node)
    return nil unless node
    { "href" => node["href"] }.compact
  end

  def system_id_to_hash(node)
    return nil unless node
    {
      "identifier-type" => node["identifier-type"],
      "id"              => node.text.strip
    }.compact
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
      }.presence,
      "origins"     => parse_origins(node),
      "props"       => parse_props(node),
      "links"       => parse_links(node)
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
            { "name" => f["name"], "value" => f["value"], "system" => f["system"] }.compact
          }
        }
      }.presence,
      "mitigating-factors" => node.xpath("xmlns:mitigating-factor", "xmlns" => OSCAL_NS).map { |mf|
        { "uuid" => mf["uuid"], "description" => text(mf, "description") }.compact
      }.presence,
      "origins"     => parse_origins(node),
      "threat-ids"  => node.xpath("xmlns:threat-id", "xmlns" => OSCAL_NS).map { |t|
        { "system" => t["system"], "href" => t["href"], "id" => t.text.strip }.compact
      }.presence,
      "risk-log"    => risk_log_to_hash(node.at_xpath("xmlns:risk-log", "xmlns" => OSCAL_NS)),
      "remediations" => node.xpath("xmlns:response", "xmlns" => OSCAL_NS).map { |r|
        remediation_to_hash(r)
      }.presence,
      "related-observations" => node.xpath("xmlns:related-observation", "xmlns" => OSCAL_NS).map { |ro|
        { "observation-uuid" => ro["observation-uuid"] }
      }.presence,
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  def remediation_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "lifecycle"   => node["lifecycle"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "origins"     => parse_origins(node),
      "required-assets" => node.xpath("xmlns:required-asset", "xmlns" => OSCAL_NS).map { |ra|
        { "uuid" => ra["uuid"], "description" => text(ra, "description") }.compact
      }.presence,
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks"),
      "tasks"       => node.xpath("xmlns:task", "xmlns" => OSCAL_NS).map { |t|
        task_to_hash(t)
      }.presence
    }.compact
  end

  def task_to_hash(node)
    timing_node = node.at_xpath("xmlns:timing", "xmlns" => OSCAL_NS)
    timing = {}
    if timing_node
      range = timing_node.at_xpath("xmlns:within-date-range", "xmlns" => OSCAL_NS)
      on_date = timing_node.at_xpath("xmlns:on-date", "xmlns" => OSCAL_NS)
      if range
        timing["within-date-range"] = { "start" => range["start"], "end" => range["end"] }.compact
      elsif on_date
        timing["on-date"] = { "date" => on_date["date"] }
      end
    end

    {
      "uuid"        => node["uuid"],
      "type"        => node["type"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "timing"      => timing.presence,
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks"),
      "responsible-roles" => node.xpath("xmlns:responsible-role", "xmlns" => OSCAL_NS).map { |rr|
        { "role-id" => rr["role-id"] }
      }.presence,
      "subjects"    => node.xpath("xmlns:subject", "xmlns" => OSCAL_NS).map { |s|
        { "subject-uuid" => s["subject-uuid"], "type" => s["type"] }
      }.presence
    }.compact
  end

  def finding_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "target"      => target_to_hash(node.at_xpath("xmlns:target", "xmlns" => OSCAL_NS)),
      "implementation-statement-uuid" => node.at_xpath("xmlns:implementation-statement-uuid", "xmlns" => OSCAL_NS)&.text&.strip,
      "origins"     => parse_origins(node),
      "related-observations" => node.xpath("xmlns:related-observation", "xmlns" => OSCAL_NS).map { |ro|
        { "observation-uuid" => ro["observation-uuid"] }
      }.presence,
      "related-risks" => node.xpath("xmlns:associated-risk", "xmlns" => OSCAL_NS).map { |rr|
        { "risk-uuid" => rr["risk-uuid"] }
      }.presence,
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  def target_to_hash(node)
    return {} unless node
    {
      "type"             => node["type"],
      "target-id"        => node["target-id"],
      "status"           => { "state" => text(node, "status") }.compact.presence,
      "implementation-status" => text(node, "implementation-status")
    }.compact
  end

  def poam_item_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "origins"     => parse_origins(node),
      "related-observations" => node.xpath("xmlns:related-observation", "xmlns" => OSCAL_NS).map { |ro|
        { "observation-uuid" => ro["observation-uuid"] }
      }.presence,
      "related-risks" => node.xpath("xmlns:associated-risk", "xmlns" => OSCAL_NS).map { |rr|
        { "risk-uuid" => rr["risk-uuid"] }
      }.presence,
      "related-findings" => node.xpath("xmlns:related-finding", "xmlns" => OSCAL_NS).map { |rf|
        { "finding-uuid" => rf["finding-uuid"] }
      }.presence,
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  def local_definitions_to_hash(node)
    return nil unless node
    {
      "components" => node.xpath("xmlns:component", "xmlns" => OSCAL_NS).map { |c|
        comp_status = c.at_xpath("xmlns:status", "xmlns" => OSCAL_NS)
        {
          "uuid"        => c["uuid"],
          "type"        => c["type"],
          "title"       => text(c, "title"),
          "description" => text(c, "description"),
          "purpose"     => text(c, "purpose"),
          "status"      => comp_status ? { "state" => comp_status["state"], "remarks" => text(comp_status, "remarks") }.compact : nil,
          "responsible-roles" => c.xpath("xmlns:responsible-role", "xmlns" => OSCAL_NS).map { |rr|
            { "role-id" => rr["role-id"] }
          }.presence,
          "protocols"   => c.xpath("xmlns:protocol", "xmlns" => OSCAL_NS).map { |p|
            { "uuid" => p["uuid"], "name" => p["name"] }.compact
          }.presence,
          "props"       => parse_props(c),
          "links"       => parse_links(c),
          "remarks"     => text(c, "remarks")
        }.compact
      }.presence,
      "inventory-items" => node.xpath("xmlns:inventory-item", "xmlns" => OSCAL_NS).map { |ii|
        { "uuid" => ii["uuid"], "description" => text(ii, "description") }.compact
      }.presence,
      "assessment-assets" => assessment_assets_to_hash(node.at_xpath("xmlns:assessment-assets", "xmlns" => OSCAL_NS))
    }.compact.presence
  end

  def assessment_assets_to_hash(node)
    return nil unless node
    { "components" => node.xpath("xmlns:component", "xmlns" => OSCAL_NS).map { |c| { "uuid" => c["uuid"] } } }.compact.presence
  end

  def risk_log_to_hash(node)
    return {} unless node
    {
      "entries" => node.xpath("xmlns:entry", "xmlns" => OSCAL_NS).map { |e|
        {
          "uuid"        => e["uuid"],
          "title"       => text(e, "title"),
          "description" => text(e, "description"),
          "start"       => text(e, "start"),
          "end"         => text(e, "end")
        }.compact
      }
    }
  end

  def back_matter_to_hash(node)
    return nil unless node
    {
      "resources" => node.xpath("xmlns:resource", "xmlns" => OSCAL_NS).map { |r|
        {
          "uuid"   => r["uuid"],
          "title"  => text(r, "title"),
          "rlinks" => r.xpath("xmlns:rlink", "xmlns" => OSCAL_NS).map { |rl|
            { "href" => rl["href"] }.compact
          }.presence
        }.compact
      }
    }
  end

  # ── Common XML helpers ──────────────────────────────────────────

  def parse_props(node)
    node.xpath("xmlns:prop", "xmlns" => OSCAL_NS).map { |p|
      { "name" => p["name"], "value" => p["value"], "ns" => p["ns"], "class" => p["class"], "uuid" => p["uuid"] }.compact
    }.presence
  end

  def parse_links(node)
    node.xpath("xmlns:link", "xmlns" => OSCAL_NS).map { |l|
      { "href" => l["href"], "rel" => l["rel"], "media-type" => l["media-type"] }.compact
    }.presence
  end

  def parse_origins(node)
    node.xpath("xmlns:origin", "xmlns" => OSCAL_NS).map { |o|
      {
        "actors" => o.xpath("xmlns:actor", "xmlns" => OSCAL_NS).map { |a|
          { "type" => a["type"], "actor-uuid" => a["actor-uuid"] }.compact
        }
      }
    }.presence
  end

  def text(node, child_name)
    return nil unless node
    child = node.at_xpath("xmlns:#{child_name}", "xmlns" => OSCAL_NS)
    child&.text&.strip&.presence
  end
end
