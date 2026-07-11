class ProfileJsonParserService
  include BatchInsertable
  include ProgressTrackable
  include BackMatterPromotable

  def initialize(profile_document, file_path)
    @document  = profile_document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)

    # Detect resolved profile catalogs (NIST-published baselines with catalog root key)
    if data["catalog"] && resolved_profile_catalog?(data["catalog"])
      return parse_resolved_catalog(data["catalog"], data)
    end

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
      # Store the raw OSCAL id directly — it now matches catalog_controls.control_id natively.
      alter    = alter_map[raw_id]
      priority = extract_priority(alter)

      attrs = {
        control_id:     raw_id,
        title:          nil,
        priority:       priority,
        control_family: raw_id.split("-").first.upcase.presence,
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

    update_processing_stage!(:creating_records)
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
    else nil # title without a baseline keyword
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
        "merge"        => profile["merge"]
      }.compact
    )
    @document.assign_oscal_uuid!(profile["uuid"])

    # #583 — promote OSCAL back-matter to first-class BackMatterResource
    # rows. `back_matter` (the raw OSCAL array) is still passed to
    # link_source_catalog because that helper inspects href patterns
    # in the raw resources to find a matching ControlCatalog.
    promote_back_matter_resources(back_matter)

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

  def extract_priority(alter)
    return nil unless alter
    (alter["adds"] || []).each do |add|
      (add["props"] || []).each do |prop|
        return prop["value"] if prop["name"] == "priority"
      end
    end
    nil
  end

  # ── Resolved Profile Catalog Support ─────────────────────────────────
  #
  # NIST publishes "resolved profile catalogs" — fully expanded baselines
  # that have a "catalog" root key (not "profile"). They contain groups
  # with controls already resolved from the source catalog + profile
  # modifications. These should be accepted as-is, auto-published, and
  # not require P1/P2/P3 prioritization.

  # Detect whether a catalog-rooted document is a resolved profile.
  # Heuristic: metadata contains a resolution-tool prop OR a source-profile link.
  def resolved_profile_catalog?(catalog)
    metadata = catalog["metadata"] || {}
    props = metadata["props"] || []
    links = metadata["links"] || []

    props.any? { |p| p["name"] == "resolution-tool" } ||
      links.any? { |l| l["rel"] == "source-profile" }
  end

  # Parse a resolved profile catalog — controls come from groups[], not imports[].
  def parse_resolved_catalog(catalog, full_data)
    metadata = catalog["metadata"] || {}
    groups   = catalog["groups"] || []

    update_resolved_metadata(metadata, catalog)
    link_catalog_from_source_profile(metadata)

    control_attrs = []
    field_entries = []
    row_order     = 0

    groups.each do |group|
      family = group["id"]&.upcase || group["title"]&.split(" ")&.first&.upcase

      extract_controls_from_group(group, family, control_attrs, field_entries, row_order)
      row_order = control_attrs.size
    end

    update_processing_stage!(:creating_records)
    batch_insert_records(
      control_class: ProfileControl,
      field_class:   ProfileControlField,
      document_fk:   :profile_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )

    # Store the entire resolved catalog JSON directly — it IS the resolved catalog
    @document.update!(resolved_catalog_json: full_data)
  end

  def update_resolved_metadata(metadata, catalog)
    title = metadata["title"] || ""
    baseline = case title
    when /LOW/i      then "LOW"
    when /MODERATE/i then "MODERATE"
    when /HIGH/i     then "HIGH"
    else nil # title without a baseline keyword
    end

    source_profile_href = (metadata["links"] || [])
      .find { |l| l["rel"] == "source-profile" }&.dig("href")

    # Preserve full OSCAL metadata (roles, parties, revisions, etc.)
    metadata_extra = metadata.except("title", "version", "oscal-version", "last-modified")
    metadata_extra["auto_publish"] = true

    @document.update!(
      description:     title,
      baseline_level:  baseline,
      profile_version: metadata["version"],
      oscal_version:   metadata["oscal-version"],
      metadata_extra:  metadata_extra.presence || {},
      import_metadata: {
        "format"               => "oscal_resolved_profile",
        "uuid"                 => catalog["uuid"],
        "source_profile_href"  => source_profile_href
      }.compact
    )
    @document.assign_oscal_uuid!(catalog["uuid"])

    # #583 — promote OSCAL back-matter to first-class BackMatterResource rows.
    promote_back_matter_resources(catalog.dig("back-matter", "resources"))
  end

  # Link to source catalog by matching the source-profile filename against catalog names.
  # Resolved profiles reference their source profile (not catalog) in metadata links,
  # but the filename pattern reveals the catalog revision (e.g., "rev5", "800-53").
  def link_catalog_from_source_profile(metadata)
    return if @document.control_catalog_id.present?

    source_href = (metadata["links"] || [])
      .find { |l| l["rel"] == "source-profile" }&.dig("href")
    return unless source_href.present?

    href_lower = source_href.downcase
    catalogs = ControlCatalog.all
    return if catalogs.none?

    catalogs.each do |catalog|
      catalog_name = catalog.name.downcase
      href_rev = href_lower[/rev\.?\s*(\d+)/i, 1]
      catalog_rev = catalog_name[/rev\.?\s*(\d+)/i, 1]

      if href_lower.include?("800-53") && catalog_name.include?("800-53") &&
          href_rev.present? && catalog_rev.present? && href_rev == catalog_rev
        @document.update_column(:control_catalog_id, catalog.id)
        return
      end
    end

    # Fall back to back-matter matching — #583 reads from promoted
    # BackMatterResource rows (was import_metadata stash). The helper
    # expects raw OSCAL hashes, so we reconstruct the shape from the
    # promoted rows.
    back_matter = @document.back_matter_resources.map do |bmr|
      { "uuid" => bmr.uuid, "title" => bmr.title,
        "rlinks" => bmr.href.present? ? [ { "href" => bmr.href, "media-type" => bmr.media_type } ] : nil }.compact
    end
    link_source_catalog(nil, back_matter) if back_matter.any?
  end

  # Recursively extract controls from a group (handles control enhancements as nested controls).
  def extract_controls_from_group(group, family, control_attrs, field_entries, row_order)
    (group["controls"] || []).each do |control|
      row_order = add_resolved_control(control, family, control_attrs, field_entries, row_order)

      # Control enhancements are nested controls
      (control["controls"] || []).each do |enhancement|
        row_order = add_resolved_control(enhancement, family, control_attrs, field_entries, row_order)
      end
    end
  end

  def add_resolved_control(control, family, control_attrs, field_entries, row_order)
    control_id = control["id"]
    priority = (control["props"] || []).find { |p| p["name"] == "priority" }&.dig("value")

    attrs = {
      control_id:     control_id,
      title:          control["title"],
      priority:       priority,
      control_family: family || control_id&.split("-")&.first&.upcase,
      row_order:      row_order
    }

    idx = control_attrs.size
    control_attrs << attrs

    # Store props as fields (skip priority — stored on control)
    (control["props"] || []).each do |prop|
      next if prop["name"] == "priority"
      field_entries << [ idx, "prop:#{prop['name']}", prop["value"] ] if prop["value"].present?
    end

    # Store parameters as fields
    (control["params"] || []).each do |param|
      param_id = param["id"]
      next unless param_id

      label = param["label"]
      field_entries << [ idx, "parameter_label:#{param_id}", label ] if label.present?

      # Store select choices if present
      if param["select"]
        choices = Array(param.dig("select", "choice")).join(", ")
        field_entries << [ idx, "parameter:#{param_id}", choices ] if choices.present?
      end

      # Store guidelines
      (param["guidelines"] || []).each_with_index do |g, gi|
        field_entries << [ idx, "parameter_guideline:#{param_id}:#{gi}", g["prose"] ] if g["prose"].present?
      end
    end

    row_order + 1
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
