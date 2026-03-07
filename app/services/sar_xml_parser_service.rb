# Parses an OSCAL Assessment Results XML file by converting XML nodes to
# intermediate hashes then delegating to SarJsonParserService#parse_from_hash.
#
class SarXmlParserService
  OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0".freeze

  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    xml = File.read(@file_path).force_encoding("UTF-8")
    doc = Nokogiri::XML(xml) { |config| config.noblanks }
    root = doc.at_xpath("xmlns:assessment-results", "xmlns" => OSCAL_NS) ||
           doc.at_xpath("assessment-results") ||
           raise("Invalid OSCAL Assessment Results XML: missing <assessment-results> root")

    ar_hash = build_ar_hash(root)
    data = { "assessment-results" => ar_hash }

    json_parser = SarJsonParserService.new(@document, nil)
    json_parser.parse_from_hash(data)
  end

  private

  # ── Top-level assembly ───────────────────────────────────────────

  def build_ar_hash(root)
    {
      "uuid"              => root["uuid"],
      "metadata"          => metadata_to_hash(root.at_xpath("xmlns:metadata", ns)),
      "import-ap"         => import_ap_to_hash(root.at_xpath("xmlns:import-ap", ns)),
      "local-definitions" => local_definitions_to_hash(root.at_xpath("xmlns:local-definitions", ns)),
      "results"           => root.xpath("xmlns:result", ns).map { |r| result_to_hash(r) },
      "back-matter"       => back_matter_to_hash(root.at_xpath("xmlns:back-matter", ns))
    }.compact
  end

  # ── Metadata ──────────────────────────────────────────────────

  def metadata_to_hash(node)
    return nil unless node
    {
      "title"         => text(node, "title"),
      "version"       => text(node, "version"),
      "oscal-version" => text(node, "oscal-version"),
      "last-modified" => text(node, "last-modified"),
      "revisions"     => node.xpath("xmlns:revisions/xmlns:revision", ns).map { |r| revision_to_hash(r) }.presence,
      "roles"         => node.xpath("xmlns:role", ns).map { |r| role_to_hash(r) },
      "parties"       => node.xpath("xmlns:party", ns).map { |p| party_to_hash(p) },
      "responsible-parties" => node.xpath("xmlns:responsible-party", ns).map { |rp| responsible_party_to_hash(rp) },
      "remarks"       => text(node, "remarks")
    }.compact
  end

  def revision_to_hash(node)
    {
      "title"         => text(node, "title"),
      "version"       => text(node, "version"),
      "oscal-version" => text(node, "oscal-version"),
      "last-modified" => text(node, "last-modified"),
      "links"         => parse_links(node),
      "remarks"       => text(node, "remarks")
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
      "member-of-organizations" => node.xpath("xmlns:member-of-organization", ns).map(&:text).presence
    }.compact
  end

  def responsible_party_to_hash(node)
    {
      "role-id"     => node["role-id"],
      "party-uuids" => node.xpath("xmlns:party-uuid", ns).map(&:text)
    }.compact
  end

  # ── Import AP ──────────────────────────────────────────────────

  def import_ap_to_hash(node)
    return nil unless node
    { "href" => node["href"] }.compact
  end

  # ── Local definitions ──────────────────────────────────────────

  def local_definitions_to_hash(node)
    return nil unless node
    {
      "components" => node.xpath("xmlns:component", ns).map { |c| component_to_hash(c) },
      "activities" => node.xpath("xmlns:activity", ns).map { |a| activity_to_hash(a) }
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
      "protocols"         => node.xpath("xmlns:protocol", ns).map { |p| { "uuid" => p["uuid"], "name" => p["name"] }.compact },
      "props"             => parse_props(node),
      "links"             => parse_links(node),
      "remarks"           => text(node, "remarks")
    }.compact
  end

  def activity_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "steps"       => node.xpath("xmlns:step", ns).map { |s| step_to_hash(s) },
      "related-controls" => related_controls_to_hash(node.at_xpath("xmlns:related-controls", ns)),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  def step_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  # ── Result ─────────────────────────────────────────────────────

  def result_to_hash(node)
    {
      "uuid"              => node["uuid"],
      "title"             => text(node, "title"),
      "description"       => text(node, "description"),
      "start"             => text(node, "start"),
      "end"               => text(node, "end"),
      "reviewed-controls" => reviewed_controls_to_hash(node.at_xpath("xmlns:reviewed-controls", ns)),
      "assessment-log"    => assessment_log_to_hash(node.at_xpath("xmlns:assessment-log", ns)),
      "attestations"      => node.xpath("xmlns:attestation", ns).map { |a| attestation_to_hash(a) },
      "observations"      => node.xpath("xmlns:observation", ns).map { |o| observation_to_hash(o) },
      "risks"             => node.xpath("xmlns:risk", ns).map { |r| risk_to_hash(r) },
      "findings"          => node.xpath("xmlns:finding", ns).map { |f| finding_to_hash(f) },
      "props"             => parse_props(node),
      "links"             => parse_links(node),
      "remarks"           => text(node, "remarks")
    }.compact
  end

  def reviewed_controls_to_hash(node)
    return nil unless node
    {
      "control-selections" => node.xpath("xmlns:control-selection", ns).map { |cs| control_selection_to_hash(cs) },
      "control-objective-selections" => node.xpath("xmlns:control-objective-selection", ns).map { |cos| control_objective_selection_to_hash(cos) }.presence
    }.compact
  end

  def control_selection_to_hash(node)
    {
      "description"      => text(node, "description"),
      "include-all"      => node.at_xpath("xmlns:include-all", ns) ? {} : nil,
      "include-controls" => node.xpath("xmlns:include-control", ns).map { |c| { "control-id" => c["control-id"] } },
      "exclude-controls" => node.xpath("xmlns:exclude-control", ns).map { |c| { "control-id" => c["control-id"] } }.presence
    }.compact
  end

  def control_objective_selection_to_hash(node)
    {
      "include-all"       => node.at_xpath("xmlns:include-all", ns) ? {} : nil,
      "include-objectives" => node.xpath("xmlns:include-objective", ns).map { |o| { "objective-id" => o["objective-id"] } }.presence
    }.compact
  end

  def related_controls_to_hash(node)
    return nil unless node
    reviewed_controls_to_hash(node)
  end

  def assessment_log_to_hash(node)
    return nil unless node
    {
      "entries" => node.xpath("xmlns:entry", ns).map { |e| log_entry_to_hash(e) }
    }.compact
  end

  def log_entry_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "start"       => text(node, "start"),
      "end"         => text(node, "end"),
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  def attestation_to_hash(node)
    {
      "responsible-parties" => node.xpath("xmlns:responsible-party", ns).map { |rp| responsible_party_to_hash(rp) },
      "parts"               => node.xpath("xmlns:part", ns).map { |p| part_to_hash(p) }
    }.compact
  end

  def part_to_hash(node)
    {
      "uuid"  => node["uuid"],
      "name"  => node["name"],
      "title" => text(node, "title"),
      "prose" => text(node, "p") || node.text.presence,
      "props" => parse_props(node),
      "links" => parse_links(node),
      "parts" => node.xpath("xmlns:part", ns).map { |p| part_to_hash(p) }.presence
    }.compact
  end

  # ── Observation ────────────────────────────────────────────────

  def observation_to_hash(node)
    {
      "uuid"               => node["uuid"],
      "title"              => text(node, "title"),
      "description"        => text(node, "description"),
      "methods"            => node.xpath("xmlns:method", ns).map(&:text),
      "types"              => node.xpath("xmlns:type", ns).map(&:text),
      "origins"            => node.xpath("xmlns:origin", ns).map { |o| origin_to_hash(o) },
      "subjects"           => node.xpath("xmlns:subject", ns).map { |s| subject_to_hash(s) },
      "relevant-evidence"  => node.xpath("xmlns:relevant-evidence", ns).map { |re| relevant_evidence_to_hash(re) },
      "collected"          => text(node, "collected"),
      "expires"            => text(node, "expires"),
      "props"              => parse_props(node),
      "links"              => parse_links(node),
      "remarks"            => text(node, "remarks")
    }.compact
  end

  def origin_to_hash(node)
    {
      "actors" => node.xpath("xmlns:actor", ns).map { |a| { "type" => a["type"], "actor-uuid" => a["actor-uuid"] }.compact }
    }.compact
  end

  def subject_to_hash(node)
    {
      "subject-uuid" => node["subject-uuid"],
      "type"         => node["type"],
      "title"        => text(node, "title"),
      "props"        => parse_props(node),
      "links"        => parse_links(node),
      "remarks"      => text(node, "remarks")
    }.compact
  end

  def relevant_evidence_to_hash(node)
    {
      "href"        => node["href"],
      "description" => text(node, "description"),
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  # ── Risk ───────────────────────────────────────────────────────

  def risk_to_hash(node)
    {
      "uuid"                 => node["uuid"],
      "title"                => text(node, "title"),
      "description"          => text(node, "description"),
      "statement"            => text(node, "statement"),
      "status"               => text(node, "status"),
      "origins"              => node.xpath("xmlns:origin", ns).map { |o| origin_to_hash(o) },
      "threat-ids"           => node.xpath("xmlns:threat-id", ns).map { |t| { "system" => t["system"], "href" => t["href"], "id" => t.text }.compact },
      "characterizations"    => node.xpath("xmlns:characterization", ns).map { |c| characterization_to_hash(c) },
      "mitigating-factors"   => node.xpath("xmlns:mitigating-factor", ns).map { |m| mitigating_factor_to_hash(m) },
      "deadline"             => text(node, "deadline"),
      "remediations"         => node.xpath("xmlns:remediation", ns).map { |r| remediation_to_hash(r) },
      "risk-log"             => risk_log_to_hash(node.at_xpath("xmlns:risk-log", ns)),
      "related-observations" => node.xpath("xmlns:related-observation", ns).map { |ro| { "observation-uuid" => ro["observation-uuid"] } },
      "props"                => parse_props(node),
      "links"                => parse_links(node),
      "remarks"              => text(node, "remarks")
    }.compact
  end

  def characterization_to_hash(node)
    {
      "origin" => origin_to_hash(node.at_xpath("xmlns:origin", ns)),
      "facets" => node.xpath("xmlns:facet", ns).map { |f| { "name" => f["name"], "system" => f["system"], "value" => f["value"] }.compact }
    }.compact
  end

  def mitigating_factor_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "description" => text(node, "description"),
      "props"       => parse_props(node),
      "links"       => parse_links(node)
    }.compact
  end

  def remediation_to_hash(node)
    {
      "uuid"        => node["uuid"],
      "lifecycle"   => node["lifecycle"],
      "title"       => text(node, "title"),
      "description" => text(node, "description"),
      "props"       => parse_props(node),
      "links"       => parse_links(node),
      "remarks"     => text(node, "remarks")
    }.compact
  end

  def risk_log_to_hash(node)
    return nil unless node
    {
      "entries" => node.xpath("xmlns:entry", ns).map { |e| log_entry_to_hash(e) }
    }.compact
  end

  # ── Finding ────────────────────────────────────────────────────

  def finding_to_hash(node)
    {
      "uuid"                          => node["uuid"],
      "title"                         => text(node, "title"),
      "description"                   => text(node, "description"),
      "target"                        => target_to_hash(node.at_xpath("xmlns:target", ns)),
      "implementation-statement-uuid" => node["implementation-statement-uuid"],
      "origins"                       => node.xpath("xmlns:origin", ns).map { |o| origin_to_hash(o) },
      "related-observations"          => node.xpath("xmlns:related-observation", ns).map { |ro| { "observation-uuid" => ro["observation-uuid"] } },
      "related-risks"                 => node.xpath("xmlns:associated-risk|xmlns:related-risk", ns).map { |rr| { "risk-uuid" => rr["risk-uuid"] } },
      "props"                         => parse_props(node),
      "links"                         => parse_links(node),
      "remarks"                       => text(node, "remarks")
    }.compact
  end

  def target_to_hash(node)
    return nil unless node
    status_node = node.at_xpath("xmlns:status", ns)
    {
      "type"      => node["type"],
      "target-id" => node["target-id"],
      "title"     => text(node, "title"),
      "status"    => status_node ? { "state" => status_node["state"], "reason" => status_node["reason"], "remarks" => text(status_node, "remarks") }.compact : nil,
      "props"     => parse_props(node),
      "links"     => parse_links(node)
    }.compact
  end

  # ── Back matter ────────────────────────────────────────────────

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
