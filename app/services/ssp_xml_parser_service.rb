# Parses an OSCAL SSP XML file by converting XML nodes to intermediate hashes
# then delegating to SspJsonParserService#parse_from_hash.
#
# Follows the same delegation pattern as PoamXmlParserService.
#
class SspXmlParserService
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
    root = doc.at_xpath("xmlns:system-security-plan", "xmlns" => OSCAL_NS) ||
           doc.at_xpath("system-security-plan") ||
           raise("Invalid OSCAL SSP XML: missing <system-security-plan> root")

    ssp_hash = build_ssp_hash(root)
    data = { "system-security-plan" => ssp_hash }

    update_processing_stage!(:creating_records)
    json_parser = SspJsonParserService.new(@document, nil)
    json_parser.parse_from_hash(data)
  end

  private

  # ── Top-level assembly ───────────────────────────────────────────

  def build_ssp_hash(root)
    {
      "uuid"                     => root["uuid"],
      "metadata"                 => metadata_to_hash(root.at_xpath("xmlns:metadata", ns)),
      "import-profile"           => import_profile_to_hash(root.at_xpath("xmlns:import-profile", ns)),
      "system-characteristics"   => system_characteristics_to_hash(root.at_xpath("xmlns:system-characteristics", ns)),
      "system-implementation"    => system_implementation_to_hash(root.at_xpath("xmlns:system-implementation", ns)),
      "control-implementation"   => control_implementation_to_hash(root.at_xpath("xmlns:control-implementation", ns)),
      "back-matter"              => back_matter_to_hash(root.at_xpath("xmlns:back-matter", ns))
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
      "responsible-parties" => node.xpath("xmlns:responsible-party", ns).map { |rp| responsible_party_to_hash(rp) }
    }.compact
  end

  def role_to_hash(node)
    { "id" => node["id"], "title" => text(node, "title") }.compact
  end

  def party_to_hash(node)
    {
      "uuid" => node["uuid"],
      "type" => node["type"],
      "name" => text(node, "name")
    }.compact
  end

  def responsible_party_to_hash(node)
    {
      "role-id"     => node["role-id"],
      "party-uuids" => node.xpath("xmlns:party-uuid", ns).map(&:text)
    }.compact
  end

  # ── Import profile ──────────────────────────────────────────────

  def import_profile_to_hash(node)
    return nil unless node
    { "href" => node["href"] }.compact
  end

  # ── System characteristics ──────────────────────────────────────

  def system_characteristics_to_hash(node)
    return nil unless node
    {
      "system-ids"              => node.xpath("xmlns:system-id", ns).map { |s| { "id" => s.text, "identifier-type" => s["identifier-type"] }.compact },
      "system-name"             => text(node, "system-name"),
      "system-name-short"       => text(node, "system-name-short"),
      "description"             => text(node, "description"),
      "security-sensitivity-level" => text(node, "security-sensitivity-level"),
      "system-information"      => system_information_to_hash(node.at_xpath("xmlns:system-information", ns)),
      "security-impact-level"   => security_impact_level_to_hash(node.at_xpath("xmlns:security-impact-level", ns)),
      "status"                  => status_to_hash(node.at_xpath("xmlns:status", ns)),
      "date-authorized"         => text(node, "date-authorized"),
      "authorization-boundary"  => boundary_to_hash(node.at_xpath("xmlns:authorization-boundary", ns)),
      "network-architecture"    => boundary_to_hash(node.at_xpath("xmlns:network-architecture", ns)),
      "data-flow"               => boundary_to_hash(node.at_xpath("xmlns:data-flow", ns)),
      "responsible-parties"     => node.xpath("xmlns:responsible-party", ns).map { |rp| responsible_party_to_hash(rp) },
      "props"                   => parse_props(node),
      "links"                   => parse_links(node)
    }.compact
  end

  def system_information_to_hash(node)
    return nil unless node
    {
      "information-types" => node.xpath("xmlns:information-type", ns).map { |it| information_type_to_hash(it) },
      "props"             => parse_props(node)
    }.compact
  end

  def information_type_to_hash(node)
    {
      "uuid"                    => node["uuid"],
      "title"                   => text(node, "title"),
      "description"             => text(node, "description"),
      "categorizations"         => node.xpath("xmlns:categorization", ns).map { |c| categorization_to_hash(c) },
      "confidentiality-impact"  => impact_to_hash(node.at_xpath("xmlns:confidentiality-impact", ns)),
      "integrity-impact"        => impact_to_hash(node.at_xpath("xmlns:integrity-impact", ns)),
      "availability-impact"     => impact_to_hash(node.at_xpath("xmlns:availability-impact", ns))
    }.compact
  end

  def categorization_to_hash(node)
    {
      "system"          => node["system"],
      "information-type-ids" => node.xpath("xmlns:information-type-id", ns).map(&:text)
    }.compact
  end

  def impact_to_hash(node)
    return nil unless node
    {
      "base"                    => text(node, "base"),
      "selected"                => text(node, "selected"),
      "adjustment-justification" => text(node, "adjustment-justification")
    }.compact
  end

  def security_impact_level_to_hash(node)
    return nil unless node
    {
      "security-objective-confidentiality" => text(node, "security-objective-confidentiality"),
      "security-objective-integrity"       => text(node, "security-objective-integrity"),
      "security-objective-availability"    => text(node, "security-objective-availability")
    }.compact
  end

  def status_to_hash(node)
    return nil unless node
    { "state" => node["state"], "remarks" => text(node, "remarks") }.compact
  end

  def boundary_to_hash(node)
    return nil unless node
    { "description" => text(node, "description") }.compact
  end

  # ── System implementation ───────────────────────────────────────

  def system_implementation_to_hash(node)
    return nil unless node
    {
      "users"                     => node.xpath("xmlns:user", ns).map { |u| user_to_hash(u) },
      "components"                => node.xpath("xmlns:component", ns).map { |c| component_to_hash(c) },
      "leveraged-authorizations"  => node.xpath("xmlns:leveraged-authorization", ns).map { |la| leveraged_auth_to_hash(la) },
      "inventory-items"           => node.xpath("xmlns:inventory-item", ns).map { |ii| inventory_item_to_hash(ii) },
      "props"                     => parse_props(node),
      "links"                     => parse_links(node)
    }.compact
  end

  def user_to_hash(node)
    {
      "uuid"                   => node["uuid"],
      "title"                  => text(node, "title"),
      "description"            => text(node, "description"),
      "short-name"             => text(node, "short-name"),
      "role-ids"               => node.xpath("xmlns:role-id", ns).map(&:text),
      "authorized-privileges"  => node.xpath("xmlns:authorized-privilege", ns).map { |ap| authorized_privilege_to_hash(ap) },
      "props"                  => parse_props(node),
      "links"                  => parse_links(node),
      "remarks"                => text(node, "remarks")
    }.compact
  end

  def authorized_privilege_to_hash(node)
    {
      "title"               => text(node, "title"),
      "functions-performed" => node.xpath("xmlns:function-performed", ns).map(&:text)
    }.compact
  end

  def component_to_hash(node)
    status_node = node.at_xpath("xmlns:status", ns)
    {
      "uuid"              => node["uuid"],
      "type"              => node["type"],
      "title"             => text(node, "title"),
      "description"       => text(node, "description"),
      "purpose"           => text(node, "purpose"),
      "status"            => status_node ? { "state" => status_node["state"], "remarks" => text(status_node, "remarks") }.compact : nil,
      "responsible-roles" => node.xpath("xmlns:responsible-role", ns).map { |rr| { "role-id" => rr["role-id"] } },
      "protocols"         => node.xpath("xmlns:protocol", ns).map { |p| protocol_to_hash(p) },
      "props"             => parse_props(node),
      "links"             => parse_links(node),
      "remarks"           => text(node, "remarks")
    }.compact
  end

  def protocol_to_hash(node)
    {
      "uuid"         => node["uuid"],
      "name"         => node["name"],
      "title"        => text(node, "title"),
      "port-ranges"  => node.xpath("xmlns:port-range", ns).map { |pr| { "start" => pr["start"]&.to_i, "end" => pr["end"]&.to_i, "transport" => pr["transport"] }.compact }
    }.compact
  end

  def leveraged_auth_to_hash(node)
    {
      "uuid"            => node["uuid"],
      "title"           => text(node, "title"),
      "party-uuid"      => text(node, "party-uuid"),
      "date-authorized" => text(node, "date-authorized"),
      "props"           => parse_props(node),
      "links"           => parse_links(node),
      "remarks"         => text(node, "remarks")
    }.compact
  end

  def inventory_item_to_hash(node)
    {
      "uuid"                   => node["uuid"],
      "description"            => text(node, "description"),
      "implemented-components" => node.xpath("xmlns:implemented-component", ns).map { |ic| { "component-uuid" => ic["component-uuid"] }.compact },
      "responsible-parties"    => node.xpath("xmlns:responsible-party", ns).map { |rp| responsible_party_to_hash(rp) },
      "props"                  => parse_props(node),
      "links"                  => parse_links(node),
      "remarks"                => text(node, "remarks")
    }.compact
  end

  # ── Control implementation ──────────────────────────────────────

  def control_implementation_to_hash(node)
    return nil unless node
    {
      "description"              => text(node, "description"),
      "implemented-requirements" => node.xpath("xmlns:implemented-requirement", ns).map { |ir| implemented_requirement_to_hash(ir) }
    }.compact
  end

  def implemented_requirement_to_hash(node)
    {
      "uuid"           => node["uuid"],
      "control-id"     => node["control-id"],
      "props"          => parse_props(node),
      "links"          => parse_links(node),
      "set-parameters" => node.xpath("xmlns:set-parameter", ns).map { |sp| set_parameter_to_hash(sp) },
      "responsible-roles" => node.xpath("xmlns:responsible-role", ns).map { |rr| { "role-id" => rr["role-id"] } },
      "statements"     => node.xpath("xmlns:statement", ns).map { |s| statement_to_hash(s) },
      "by-components"  => node.xpath("xmlns:by-component", ns).map { |bc| by_component_to_hash(bc) },
      "remarks"        => text(node, "remarks")
    }.compact
  end

  def statement_to_hash(node)
    {
      "statement-id"  => node["statement-id"],
      "uuid"          => node["uuid"],
      "by-components" => node.xpath("xmlns:by-component", ns).map { |bc| by_component_to_hash(bc) },
      "remarks"       => text(node, "remarks"),
      "props"         => parse_props(node),
      "links"         => parse_links(node)
    }.compact
  end

  def by_component_to_hash(node)
    impl_status = node.at_xpath("xmlns:implementation-status", ns)
    {
      "component-uuid"       => node["component-uuid"],
      "uuid"                 => node["uuid"],
      "description"          => text(node, "description"),
      "implementation-status" => impl_status ? { "state" => impl_status["state"], "remarks" => text(impl_status, "remarks") }.compact : nil,
      "export"               => export_to_hash(node.at_xpath("xmlns:export", ns)),
      "inherited"            => node.xpath("xmlns:inherited", ns).map { |i| inherited_to_hash(i) },
      "satisfied"            => node.xpath("xmlns:satisfied", ns).map { |s| satisfied_to_hash(s) },
      "responsible-roles"    => node.xpath("xmlns:responsible-role", ns).map { |rr| { "role-id" => rr["role-id"] } },
      "set-parameters"       => node.xpath("xmlns:set-parameter", ns).map { |sp| set_parameter_to_hash(sp) },
      "props"                => parse_props(node),
      "links"                => parse_links(node),
      "remarks"              => text(node, "remarks")
    }.compact
  end

  def export_to_hash(node)
    return nil unless node
    {
      "description"      => text(node, "description"),
      "provided"         => node.xpath("xmlns:provided", ns).map { |p| { "uuid" => p["uuid"], "description" => text(p, "description") }.compact },
      "responsibilities" => node.xpath("xmlns:responsibility", ns).map { |r| { "uuid" => r["uuid"], "provided-uuid" => r["provided-uuid"], "description" => text(r, "description") }.compact }
    }.compact
  end

  def inherited_to_hash(node)
    {
      "uuid"          => node["uuid"],
      "provided-uuid" => node["provided-uuid"],
      "description"   => text(node, "description")
    }.compact
  end

  def satisfied_to_hash(node)
    {
      "uuid"                => node["uuid"],
      "responsibility-uuid" => node["responsibility-uuid"],
      "description"         => text(node, "description")
    }.compact
  end

  def set_parameter_to_hash(node)
    {
      "param-id" => node["param-id"],
      "values"   => node.xpath("xmlns:value", ns).map(&:text)
    }.compact
  end

  # ── Back matter ─────────────────────────────────────────────────

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

  # ── Common helpers ──────────────────────────────────────────────

  def ns
    { "xmlns" => OSCAL_NS }
  end

  def text(node, child_name)
    node&.at_xpath("xmlns:#{child_name}", ns)&.text&.presence
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
