require "tempfile"

class ProfileXmlParserService
  include ProgressTrackable

  OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0".freeze
  OSCAL_VERSION = "oscal-version".freeze

  def initialize(profile_document, file_path)
    @document  = profile_document
    @file_path = file_path
  end

  # #1234 — an OSCAL profile in XML is converted to the JSON model and parsed
  # by ProfileJsonParserService, as the YAML parser already does. The XML path
  # had its own reduced import: it read the first import's href only, linked no
  # catalog at all, gave controls no titles and dropped the back-matter, so a
  # baseline imported from XML could not even name its catalog. One parser for
  # the three formats means each import links its own catalog, whatever the
  # file's format (owner, 2026-10-21: JSON, YAML and XML must all be honoured).
  def parse
    update_processing_stage!(:reading_file)
    doc = XmlSecurity.parse(File.read(@file_path))
    doc.remove_namespaces!

    # Detect resolved profile catalogs (XML with <catalog> root + resolution-tool or source-profile)
    catalog_el = doc.at_xpath("//catalog")
    if catalog_el && resolved_profile_catalog_xml?(catalog_el)
      return parse_resolved_via_json(catalog_el)
    end

    profile = doc.at_xpath("//profile") || raise(DocumentParseError, "Invalid OSCAL Profile XML: missing <profile> element")

    delegate_to_json({ "profile" => xml_profile_to_json(profile) })
    @document.reload.update_column(:import_metadata, (@document.import_metadata || {}).merge("format" => "oscal_profile_xml"))
  end

  private

  def delegate_to_json(data)
    tmp = Tempfile.new([ "profile_xml_", ".json" ])
    tmp.write(JSON.generate(data))
    tmp.close

    ProfileJsonParserService.new(@document, tmp.path).parse
  ensure
    tmp&.unlink
  end

  # The parts of an OSCAL <profile> the JSON parser reads, in the JSON model's
  # shape: metadata, imports, merge, modify and back-matter.
  def xml_profile_to_json(profile)
    {
      "uuid"        => profile["uuid"],
      "metadata"    => (xml_metadata_to_json(profile.at_xpath("metadata")) if profile.at_xpath("metadata")),
      "imports"     => profile.xpath("import").map { |imp| xml_import_to_json(imp) },
      "merge"       => xml_merge_to_json(profile.at_xpath("merge")),
      "modify"      => xml_modify_to_json(profile.at_xpath("modify")),
      "back-matter" => (xml_back_matter_to_json(profile.at_xpath("back-matter")) if profile.at_xpath("back-matter"))
    }.compact
  end

  def xml_import_to_json(imp)
    h = { "href" => imp["href"] }
    includes = imp.xpath("include-controls").map { |ic| { "with-ids" => ic.xpath("with-id").map { |w| w.text.strip } } }
    h["include-controls"] = includes if includes.any?
    h["include-all"] = {} if imp.at_xpath("include-all")
    h
  end

  def xml_merge_to_json(merge_el)
    return nil unless merge_el&.at_xpath("as-is")

    { "as-is" => true }
  end

  def xml_modify_to_json(modify)
    return nil unless modify

    set_params = modify.xpath("set-parameter").map do |param|
      h = { "param-id" => param["param-id"], "values" => param.xpath("value").map { |v| v.text.strip } }
      label = param.at_xpath("label")&.text
      h["label"] = label if label.present?
      h
    end
    alters = modify.xpath("alter").map do |alter|
      adds = alter.xpath("add").map do |add|
        { "position" => add["position"], "props" => add.xpath("prop").map { |p| xml_prop_to_json(p) } }.compact
      end
      { "control-id" => alter["control-id"], "adds" => adds }
    end

    { "set-parameters" => (set_params if set_params.any?), "alters" => (alters if alters.any?) }.compact.presence
  end

  # Detect whether a <catalog> element is a resolved profile catalog.
  def resolved_profile_catalog_xml?(catalog_el)
    metadata = catalog_el.at_xpath("metadata")
    return false unless metadata

    metadata.xpath("prop[@name='resolution-tool']").any? ||
      metadata.xpath("link[@rel='source-profile']").any?
  end

  # Convert resolved catalog XML to JSON hash and delegate to JSON parser.
  def parse_resolved_via_json(catalog_el)
    # Use Nokogiri + XSLT-free approach: convert XML to JSON hash
    json_hash = xml_catalog_to_json(catalog_el)
    full_data = { "catalog" => json_hash }

    tmp = Tempfile.new([ "resolved_profile_", ".json" ])
    tmp.write(JSON.generate(full_data))
    tmp.close

    ProfileJsonParserService.new(@document, tmp.path).parse
  ensure
    tmp&.unlink
  end

  # Convert a Nokogiri <catalog> element to a JSON-compatible hash.
  def xml_catalog_to_json(catalog_el)
    result = {}
    result["uuid"] = catalog_el["uuid"] if catalog_el["uuid"]

    metadata = catalog_el.at_xpath("metadata")
    result["metadata"] = xml_metadata_to_json(metadata) if metadata

    groups = catalog_el.xpath("group")
    result["groups"] = groups.map { |g| xml_group_to_json(g) } if groups.any?

    back_matter = catalog_el.at_xpath("back-matter")
    result["back-matter"] = xml_back_matter_to_json(back_matter) if back_matter

    result
  end

  def xml_metadata_to_json(metadata)
    h = {}
    h["title"] = metadata.at_xpath("title")&.text
    h["last-modified"] = metadata.at_xpath("last-modified")&.text
    h["version"] = metadata.at_xpath("version")&.text
    h[OSCAL_VERSION] = metadata.at_xpath(OSCAL_VERSION)&.text

    props = metadata.xpath("prop").map { |p| xml_prop_to_json(p) }
    h["props"] = props if props.any?

    links = metadata.xpath("link").map { |l| { "href" => l["href"], "rel" => l["rel"] }.compact }
    h["links"] = links if links.any?

    roles = metadata.xpath("role").map { |r| { "id" => r["id"], "title" => r.at_xpath("title")&.text }.compact }
    h["roles"] = roles if roles.any?

    parties = metadata.xpath("party").map { |p| xml_party_to_json(p) }
    h["parties"] = parties if parties.any?

    rps = metadata.xpath("responsible-party").map do |rp|
      { "role-id" => rp["role-id"], "party-uuids" => rp.xpath("party-uuid").map(&:text) }
    end
    h["responsible-parties"] = rps if rps.any?

    h.compact
  end

  def xml_party_to_json(party)
    h = { "uuid" => party["uuid"], "type" => party["type"] }
    h["name"] = party.at_xpath("name")&.text
    h["short-name"] = party.at_xpath("short-name")&.text
    emails = party.xpath("email-address").map(&:text)
    h["email-addresses"] = emails if emails.any?
    h.compact
  end

  def xml_group_to_json(group)
    h = { "id" => group["id"], "class" => group["class"], "title" => group.at_xpath("title")&.text }
    props = group.xpath("prop").map { |p| xml_prop_to_json(p) }
    h["props"] = props if props.any?

    controls = group.xpath("control").map { |c| xml_control_to_json(c) }
    h["controls"] = controls if controls.any?
    h.compact
  end

  def xml_control_to_json(control)
    h = { "id" => control["id"], "class" => control["class"], "title" => control.at_xpath("title")&.text }

    props = control.xpath("prop").map { |p| xml_prop_to_json(p) }
    h["props"] = props if props.any?

    params = control.xpath("param").map { |p| xml_param_to_json(p) }
    h["params"] = params if params.any?

    # Nested control enhancements
    nested = control.xpath("control").map { |c| xml_control_to_json(c) }
    h["controls"] = nested if nested.any?

    h.compact
  end

  def xml_prop_to_json(prop)
    h = { "name" => prop["name"], "value" => (prop["value"] || prop.text.strip) }
    h["ns"] = prop["ns"] if prop["ns"]
    h["class"] = prop["class"] if prop["class"]
    h.compact
  end

  def xml_param_to_json(param)
    h = { "id" => param["id"] }
    h["label"] = param.at_xpath("label")&.text
    select_el = param.at_xpath("select")
    if select_el
      choices = select_el.xpath("choice").map(&:text)
      h["select"] = { "how-many" => select_el["how-many"], "choice" => choices }.compact
    end
    guidelines = param.xpath("guideline").map { |g| { "prose" => g.at_xpath("p")&.text || g.text } }
    h["guidelines"] = guidelines if guidelines.any?
    props = param.xpath("prop").map { |p| xml_prop_to_json(p) }
    h["props"] = props if props.any?
    h.compact
  end

  def xml_back_matter_to_json(back_matter)
    resources = back_matter.xpath("resource").map do |r|
      res = { "uuid" => r["uuid"], "title" => r.at_xpath("title")&.text }
      rlinks = r.xpath("rlink").map { |rl| { "href" => rl["href"], "media-type" => rl["media-type"] }.compact }
      res["rlinks"] = rlinks if rlinks.any?
      res.compact
    end
    { "resources" => resources }
  end
end
