class ProfileXmlParserService
  include BatchInsertable
  include ProgressTrackable

  OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0".freeze

  def initialize(profile_document, file_path)
    @document  = profile_document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    doc = XmlSecurity.parse(File.read(@file_path))
    doc.remove_namespaces!

    # Detect resolved profile catalogs (XML with <catalog> root + resolution-tool or source-profile)
    catalog_el = doc.at_xpath("//catalog")
    if catalog_el && resolved_profile_catalog_xml?(catalog_el)
      return parse_resolved_via_json(catalog_el, doc)
    end

    profile = doc.at_xpath("//profile") || raise("Invalid OSCAL Profile XML: missing <profile> element")

    update_document_metadata(profile)

    selected_ids = extract_selected_control_ids(profile)
    alter_map    = build_alter_map(profile)
    param_map    = build_param_map(profile)

    control_attrs = []
    field_entries = []
    row_order     = 0

    selected_ids.each do |control_id|
      alter    = alter_map[control_id]
      priority = extract_priority(alter)

      attrs = {
        control_id:     control_id,
        title:          nil,
        priority:       priority,
        control_family: control_id.split("-").first.upcase.presence,
        row_order:      row_order
      }

      idx = control_attrs.size
      control_attrs << attrs

      # Store alter props as fields (skip priority — stored on control)
      if alter
        alter.xpath(".//add/prop").each do |prop|
          name  = prop["name"]
          value = prop["value"] || prop.text.strip
          next if name == "priority"
          field_entries << [ idx, "prop:#{name}", value ] if value.present?
        end
      end

      # Store matching parameters as fields
      param_map.each do |param_id, values|
        next unless param_id.start_with?("#{control_id}_")
        field_entries << [ idx, "parameter:#{param_id}", values ] if values.present?
      end

      row_order += 1
    end

    update_processing_stage!(:creating_records)
    batch_insert_records(
      control_class: ProfileControl,
      field_class:   ProfileControlField,
      document_fk:   :profile_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  private

  def update_document_metadata(profile)
    metadata = profile.at_xpath("metadata")
    title    = metadata&.at_xpath("title")&.text || ""

    baseline = case title
    when /LOW/i      then "LOW"
    when /MODERATE/i then "MODERATE"
    when /HIGH/i     then "HIGH"
    else nil # title without a baseline keyword
    end

    catalog_ref = profile.at_xpath("import")&.[]("href")
    merge_el    = profile.at_xpath("merge")
    merge_data  = if merge_el&.at_xpath("as-is")
                    { "as-is" => true }
    end

    @document.update!(
      description:     title,
      baseline_level:  baseline,
      profile_version: metadata&.at_xpath("version")&.text,
      oscal_version:   metadata&.at_xpath("oscal-version")&.text,
      import_metadata: {
        "format"       => "oscal_profile_xml",
        "uuid"         => profile["uuid"],
        "catalog_href" => catalog_ref,
        "merge"        => merge_data
      }.compact
    )
  end

  def extract_selected_control_ids(profile)
    ids = []
    profile.xpath("import/include-controls/with-id").each do |node|
      ids << node.text.strip
    end
    ids.uniq
  end

  def build_alter_map(profile)
    map = {}
    profile.xpath("modify/alter").each do |alter|
      cid = alter["control-id"]
      map[cid] = alter if cid
    end
    map
  end

  def build_param_map(profile)
    map = {}
    profile.xpath("modify/set-parameter").each do |param|
      pid = param["param-id"]
      values = param.xpath("value").map(&:text).join(", ")
      map[pid] = values if pid && values.present?
    end
    map
  end

  def extract_priority(alter)
    return nil unless alter
    alter.xpath(".//add/prop[@name='priority']").each do |prop|
      return prop["value"] || prop.text.strip
    end
    nil
  end

  # Detect whether a <catalog> element is a resolved profile catalog.
  def resolved_profile_catalog_xml?(catalog_el)
    metadata = catalog_el.at_xpath("metadata")
    return false unless metadata

    metadata.xpath("prop[@name='resolution-tool']").any? ||
      metadata.xpath("link[@rel='source-profile']").any?
  end

  # Convert resolved catalog XML to JSON hash and delegate to JSON parser.
  def parse_resolved_via_json(catalog_el, doc)
    require "tempfile"

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
    h["oscal-version"] = metadata.at_xpath("oscal-version")&.text

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
