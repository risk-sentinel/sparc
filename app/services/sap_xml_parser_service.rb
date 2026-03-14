# Parses an OSCAL Assessment Plan XML file by converting XML nodes to an
# intermediate hash, writing to a temporary JSON file, and delegating to
# SapJsonParserService#parse.
#
# SapJsonParserService does not expose a parse_from_hash method, so we
# use the temp-file delegation pattern (same as the YAML parsers for
# Pattern B document types).
#
class SapXmlParserService
  include ProgressTrackable

  OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0".freeze

  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    xml = File.read(@file_path).force_encoding("UTF-8")
    doc = Nokogiri::XML(xml) { |config| config.noblanks }
    root = doc.at_xpath("xmlns:assessment-plan", "xmlns" => OSCAL_NS) ||
           doc.at_xpath("assessment-plan") ||
           raise("Invalid OSCAL Assessment Plan XML: missing <assessment-plan> root")

    sap_hash = build_assessment_plan_hash(root)
    data = { "assessment-plan" => sap_hash }

    update_processing_stage!(:creating_records)
    tmp_json = Tempfile.new([ "sap_xml_", ".json" ])
    tmp_json.write(JSON.generate(data))
    tmp_json.close

    SapJsonParserService.new(@document, tmp_json.path).parse
  ensure
    tmp_json&.unlink
  end

  private

  # ── Top-level assembly ───────────────────────────────────────────

  def build_assessment_plan_hash(root)
    {
      "uuid"               => root["uuid"],
      "metadata"           => metadata_to_hash(root.at_xpath("xmlns:metadata", ns)),
      "import-ssp"         => import_ssp_to_hash(root.at_xpath("xmlns:import-ssp", ns)),
      "local-definitions"  => local_definitions_to_hash(root.at_xpath("xmlns:local-definitions", ns)),
      "reviewed-controls"  => reviewed_controls_to_hash(root.at_xpath("xmlns:reviewed-controls", ns)),
      "assessment-subjects" => root.xpath("xmlns:assessment-subject", ns).map { |s| assessment_subject_to_hash(s) },
      "assessment-assets"  => assessment_assets_to_hash(root.at_xpath("xmlns:assessment-assets", ns)),
      "back-matter"        => back_matter_to_hash(root.at_xpath("xmlns:back-matter", ns))
    }.compact
  end

  # ── Metadata ─────────────────────────────────────────────────────

  def metadata_to_hash(node)
    return nil unless node
    {
      "title"         => text(node, "title"),
      "version"       => text(node, "version"),
      "oscal-version" => text(node, "oscal-version"),
      "last-modified" => text(node, "last-modified"),
      "roles"         => node.xpath("xmlns:role", ns).map { |r| role_to_hash(r) },
      "parties"       => node.xpath("xmlns:party", ns).map { |p| party_to_hash(p) },
      "responsible-parties" => node.xpath("xmlns:responsible-party", ns).map { |rp| responsible_party_to_hash(rp) },
      "props"         => parse_props(node)
    }.compact
  end

  def role_to_hash(node)
    { "id" => node["id"], "title" => text(node, "title") }.compact
  end

  def party_to_hash(node)
    {
      "uuid"       => node["uuid"],
      "type"       => node["type"],
      "name"       => text(node, "name"),
      "short-name" => text(node, "short-name"),
      "links"      => parse_links(node),
      "member-of-organizations" => node.xpath("xmlns:member-of-organization", ns).map(&:text)
    }.compact
  end

  def responsible_party_to_hash(node)
    {
      "role-id"     => node["role-id"],
      "party-uuids" => node.xpath("xmlns:party-uuid", ns).map(&:text)
    }.compact
  end

  # ── Import SSP ───────────────────────────────────────────────────

  def import_ssp_to_hash(node)
    return nil unless node
    { "href" => node["href"] }.compact
  end

  # ── Local Definitions ────────────────────────────────────────────

  def local_definitions_to_hash(node)
    return nil unless node
    {
      "activities" => node.xpath("xmlns:activity", ns).map { |a| activity_to_hash(a) }
    }.compact
  end

  def activity_to_hash(node)
    {
      "uuid"             => node["uuid"],
      "title"            => text(node, "title"),
      "description"      => text(node, "description") || markup_text(node, "description"),
      "props"            => parse_props(node),
      "steps"            => node.xpath("xmlns:step", ns).map { |s| step_to_hash(s) },
      "related-controls" => reviewed_controls_to_hash(node.at_xpath("xmlns:related-controls", ns)),
      "remarks"          => text(node, "remarks")
    }.compact
  end

  def step_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description") || markup_text(node, "description"),
      "remarks"     => text(node, "remarks"),
      "props"       => parse_props(node)
    }.compact
  end

  # ── Reviewed Controls ────────────────────────────────────────────

  def reviewed_controls_to_hash(node)
    return nil unless node
    {
      "control-selections" => node.xpath("xmlns:control-selection", ns).map { |cs| control_selection_to_hash(cs) },
      "control-objective-selections" => node.xpath("xmlns:control-objective-selection", ns).map { |cos|
        {
          "include-objectives" => cos.xpath("xmlns:include-objective", ns).map { |io| { "objective-id" => io["objective-id"] } }
        }.compact
      }
    }.compact
  end

  def control_selection_to_hash(node)
    {
      "description"      => text(node, "description"),
      "include-all"      => node.at_xpath("xmlns:include-all", ns) ? {} : nil,
      "include-controls" => node.xpath("xmlns:include-control", ns).map { |ic|
        { "control-id" => ic["control-id"] }.compact
      }
    }.compact
  end

  # ── Assessment Subjects ──────────────────────────────────────────

  def assessment_subject_to_hash(node)
    {
      "type"        => node["type"],
      "description" => text(node, "description"),
      "include-all" => node.at_xpath("xmlns:include-all", ns) ? {} : nil,
      "props"       => parse_props(node)
    }.compact
  end

  # ── Assessment Assets ────────────────────────────────────────────

  def assessment_assets_to_hash(node)
    return nil unless node
    {
      "assessment-platforms" => node.xpath("xmlns:assessment-platform", ns).map { |ap|
        {
          "uuid"  => ap["uuid"],
          "title" => text(ap, "title"),
          "props" => parse_props(ap),
          "uses-components" => ap.xpath("xmlns:uses-component", ns).map { |uc|
            { "component-uuid" => uc["component-uuid"] }.compact
          }
        }.compact
      }
    }.compact
  end

  # ── Back Matter ──────────────────────────────────────────────────

  def back_matter_to_hash(node)
    return nil unless node
    {
      "resources" => node.xpath("xmlns:resource", ns).map { |r| resource_to_hash(r) }
    }.compact
  end

  def resource_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "rlinks"      => node.xpath("xmlns:rlink", ns).map { |rl| { "href" => rl["href"], "media-type" => rl["media-type"] }.compact },
      "props"       => parse_props(node),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  # ── Common helpers ───────────────────────────────────────────────

  def ns
    { "xmlns" => OSCAL_NS }
  end

  def text(node, child_name)
    node&.at_xpath("xmlns:#{child_name}", ns)&.text&.strip&.presence
  end

  # Extract markup-multiline text from a node (handles <p> children)
  def markup_text(node, child_name)
    child = node&.at_xpath("xmlns:#{child_name}", ns)
    return nil unless child
    child.xpath("xmlns:p", ns).map(&:text).join("\n").presence || child.text.strip.presence
  end

  def parse_props(node)
    node.xpath("xmlns:prop", ns).map do |p|
      { "name" => p["name"], "value" => p["value"], "ns" => p["ns"], "uuid" => p["uuid"], "class" => p["class"] }.compact
    end
  end

  def parse_links(node)
    node.xpath("xmlns:link", ns).map do |l|
      { "href" => l["href"], "rel" => l["rel"], "media-type" => l["media-type"], "text" => l.text.presence }.compact
    end
  end
end
