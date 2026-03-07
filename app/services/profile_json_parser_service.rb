class ProfileJsonParserService
  include BatchInsertable

  def initialize(profile_document, file_path)
    @document  = profile_document
    @file_path = file_path
  end

  def parse
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)

    profile = data["profile"] || raise("Invalid OSCAL Profile: missing 'profile' root key")
    metadata = profile["metadata"] || {}
    imports  = profile["imports"] || []
    modify   = profile["modify"] || {}

    update_document_metadata(metadata, imports, profile)

    selected_ids  = extract_selected_control_ids(imports)
    excluded_ids  = extract_excluded_control_ids(imports)
    alter_map     = build_alter_map(modify["alters"] || [])
    param_map     = build_param_map(modify["set-parameters"] || [])

    control_attrs = []
    field_entries = []
    row_order     = 0

    # Process included controls
    selected_ids.each do |control_id|
      alter    = alter_map[control_id]
      priority = extract_priority(alter)

      attrs = {
        control_id:     control_id,
        title:          nil,
        priority:       priority,
        control_family: control_id.split("-").first.upcase.presence,
        row_order:      row_order,
        exclude:        false,
        alters_data:    alter ? build_alters_data(alter) : [],
        additions_data: alter ? (alter["adds"] || []) : []
      }

      idx = control_attrs.size
      control_attrs << attrs

      # Store alter data as fields
      if alter
        (alter["adds"] || []).each do |add|
          (add["props"] || []).each do |prop|
            next if prop["name"] == "priority"
            field_entries << [ idx, "prop:#{prop['name']}", prop["value"] ]
          end
        end
      end

      # Store matching parameters as fields with full attributes
      param_map.each do |param_id, param_data|
        next unless param_id.start_with?("#{control_id}_")
        values = Array(param_data["values"]).join(", ")
        field_entries << [ idx, "parameter:#{param_id}", values ] if values.present?
        label = param_data["label"]
        field_entries << [ idx, "parameter_label:#{param_id}", label ] if label.present?
        # Store full parameter attributes (class, constraints, guidelines, select)
        %w[class constraints guidelines select].each do |attr|
          if param_data[attr].present?
            field_entries << [ idx, "parameter_#{attr}:#{param_id}", param_data[attr].to_json ]
          end
        end
      end

      row_order += 1
    end

    # Process excluded controls
    excluded_ids.each do |control_id|
      attrs = {
        control_id:     control_id,
        title:          nil,
        priority:       nil,
        control_family: control_id.split("-").first.upcase.presence,
        row_order:      row_order,
        exclude:        true,
        alters_data:    [],
        additions_data: []
      }
      control_attrs << attrs
      row_order += 1
    end

    batch_insert_records(
      control_class: ProfileControl,
      field_class:   ProfileControlField,
      document_fk:   :profile_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  private

  def update_document_metadata(metadata, imports, profile)
    title = metadata["title"] || ""
    baseline = case title
    when /LOW/i      then "LOW"
    when /MODERATE/i then "MODERATE"
    when /HIGH/i     then "HIGH"
    end

    catalog_ref  = imports.first&.dig("href")
    back_matter  = profile.dig("back-matter", "resources") || []

    # Preserve full OSCAL metadata (roles, parties, revisions, etc.)
    metadata_extra = metadata.except("title", "version", "oscal-version", "last-modified")

    # Check for include-all flag
    include_all = imports.any? { |imp| imp.key?("include-all") }

    @document.update!(
      description:      title,
      baseline_level:   baseline,
      profile_version:  metadata["version"],
      oscal_version:    metadata["oscal-version"],
      metadata_extra:   metadata_extra.presence || {},
      back_matter_data: back_matter,
      import_metadata:  {
        "format"       => "oscal_profile",
        "uuid"         => profile["uuid"],
        "catalog_href" => catalog_ref,
        "merge"        => profile["merge"],
        "include_all"  => include_all,
        "back_matter"  => back_matter.map { |r| { "uuid" => r["uuid"], "description" => r["description"] } }
      }.compact
    )
  end

  def extract_selected_control_ids(imports)
    ids = []
    imports.each do |imp|
      (imp["include-controls"] || []).each do |ic|
        ids.concat(Array(ic["with-ids"]))
      end
    end
    ids.uniq
  end

  def build_alter_map(alters)
    alters.each_with_object({}) do |alter, map|
      cid = alter["control-id"]
      map[cid] = alter if cid
    end
  end

  def build_param_map(set_params)
    set_params.each_with_object({}) do |param, map|
      pid = param["param-id"]
      map[pid] = param if pid
    end
  end

  def extract_priority(alter)
    return nil unless alter
    (alter["adds"] || []).each do |add|
      (add["props"] || []).each do |prop|
        return prop["value"] if prop["name"] == "priority"
      end
    end
    nil
  end

  def extract_excluded_control_ids(imports)
    ids = []
    imports.each do |imp|
      (imp["exclude-controls"] || []).each do |ec|
        ids.concat(Array(ec["with-ids"]))
      end
    end
    ids.uniq
  end

  def build_alters_data(alter)
    removes = alter["removes"] || []
    removes.map do |remove|
      {
        "by-name"  => remove["by-name"],
        "by-class" => remove["by-class"],
        "by-id"    => remove["by-id"],
        "by-ns"    => remove["by-ns"]
      }.compact
    end
  end
end
