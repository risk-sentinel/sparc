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
    doc = Nokogiri::XML(File.read(@file_path)) { |config| config.noblanks }
    doc.remove_namespaces!

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
end
