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

    selected_ids = extract_selected_control_ids(imports)
    alter_map    = build_alter_map(modify["alters"] || [])
    param_map    = build_param_map(modify["set-parameters"] || [])

    control_attrs = []
    field_entries = []
    row_order     = 0

    selected_ids.each do |raw_id|
      # Normalize to catalog format (AC-01) for cross-referencing.
      # Keep raw OSCAL ID for alter/param lookups since those use the original format.
      normalized_id = normalize_control_id(raw_id)
      alter    = alter_map[raw_id]
      priority = extract_priority(alter)

      attrs = {
        control_id:     normalized_id,
        title:          nil,
        priority:       priority,
        control_family: normalized_id.split("-").first.upcase.presence,
        row_order:      row_order
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

      # Store matching parameters as fields (raw OSCAL IDs in param keys)
      param_map.each do |param_id, param_data|
        next unless param_id.start_with?("#{raw_id}_")
        values = Array(param_data["values"]).join(", ")
        field_entries << [ idx, "parameter:#{param_id}", values ] if values.present?
        label = param_data["label"]
        field_entries << [ idx, "parameter_label:#{param_id}", label ] if label.present?
      end

      row_order += 1
    end

    batch_insert_records(
      control_class: ProfileControl,
      field_class:   ProfileControlField,
      document_fk:   :profile_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )

    # Enrich profile controls with titles from the linked catalog
    enrich_titles_from_catalog
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

    @document.update!(
      description:     title,
      baseline_level:  baseline,
      profile_version: metadata["version"],
      oscal_version:   metadata["oscal-version"],
      metadata_extra:  metadata_extra.presence || {},
      import_metadata: {
        "format"       => "oscal_profile",
        "uuid"         => profile["uuid"],
        "catalog_href" => catalog_ref,
        "merge"        => profile["merge"],
        "back_matter"  => back_matter
      }.compact
    )
    @document.assign_oscal_uuid!(profile["uuid"])

    # Auto-link to the source catalog if one is already imported
    link_source_catalog(catalog_ref, back_matter) unless @document.control_catalog_id.present?
  end

  # Attempt to find a matching ControlCatalog for this imported profile.
  #
  # OSCAL profiles reference their source catalog via:
  #   imports[].href = "#<uuid>"   (a back-matter resource UUID)
  #   back-matter.resources[uuid].rlinks[].href = "NIST_SP-800-53_rev4_catalog.json"
  #
  # Matching strategy (in priority order):
  #   1. The catalog href may directly contain the catalog's OSCAL document UUID
  #      stored in metadata_extra["catalog_uuid"].
  #   2. The back-matter resource rlinks contain filenames that can be matched
  #      against catalog names (e.g., "800-53" + "rev4" → "NIST SP 800-53 Rev 4").
  def link_source_catalog(catalog_ref, back_matter)
    catalogs = ControlCatalog.all
    return if catalogs.none?

    # Strategy 1: Direct UUID match — catalog_ref may be "#<catalog_uuid>" directly
    if catalog_ref.present?
      ref_uuid = catalog_ref.delete_prefix("#")
      match = catalogs.find { |c| c.metadata_extra&.dig("catalog_uuid") == ref_uuid }
      if match
        @document.update_column(:control_catalog_id, match.id)
        return
      end
    end

    # Strategy 2: Resolve back-matter resource and match rlinks against catalog names
    if catalog_ref&.start_with?("#") && back_matter.any?
      resource_uuid = catalog_ref.delete_prefix("#")
      resource = back_matter.find { |r| r["uuid"] == resource_uuid }

      if resource
        # Check if any rlink filename matches a known catalog
        rlinks = resource["rlinks"] || []
        rlink_hrefs = rlinks.map { |rl| rl["href"].to_s.downcase }

        catalogs.each do |catalog|
          next unless catalog_rlinks_match?(rlink_hrefs, catalog)
          @document.update_column(:control_catalog_id, catalog.id)
          return
        end
      end
    end
  end

  # Check if any rlink href contains identifiers that match a catalog.
  # Looks for revision indicators (rev4, rev5) and catalog identifiers (800-53).
  def catalog_rlinks_match?(rlink_hrefs, catalog)
    catalog_name = catalog.name.downcase

    rlink_hrefs.any? do |href|
      # Extract revision indicator from rlink (e.g., "rev4", "rev5")
      rlink_rev = href[/rev\.?\s*(\d+)/i, 1] || href[/revision[_\s]*(\d+)/i, 1]
      catalog_rev = catalog_name[/rev\.?\s*(\d+)/i, 1] || catalog_name[/revision[_\s]*(\d+)/i, 1]

      # Both must reference 800-53 and have matching revision numbers
      href.include?("800-53") && catalog_name.include?("800-53") &&
        rlink_rev.present? && catalog_rev.present? &&
        rlink_rev == catalog_rev
    end
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

  # Normalize OSCAL control IDs to match the catalog storage format:
  #   "ac-1"  → "AC-01"     (upcase + zero-pad single digits)
  #   "ac-14" → "AC-14"     (upcase only, no padding needed)
  #   "AC-01" → "AC-01"     (already normalized, no-op)
  def normalize_control_id(id)
    id.to_s.upcase.sub(/\A([A-Z]+-?)(\d+)\z/) { "#{$1}#{$2.rjust(2, '0')}" }
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

  # Populate profile control titles from the matched source catalog.
  # OSCAL profiles only reference controls by ID; titles live in the catalog.
  def enrich_titles_from_catalog
    @document.reload
    catalog = @document.control_catalog
    return unless catalog

    title_map = catalog.catalog_controls.pluck(:control_id, :title).to_h
    return if title_map.empty?

    @document.profile_controls.where(title: nil).find_each do |pc|
      mapped_title = title_map[pc.control_id]
      pc.update_column(:title, mapped_title) if mapped_title.present?
    end
  end
end
