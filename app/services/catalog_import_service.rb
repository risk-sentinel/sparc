# CatalogImportService
#
# Imports control catalogs from three supported formats:
#
#   OSCAL JSON — NIST OSCAL 1.x catalog schema
#     Source: https://github.com/usnistgov/oscal-content
#     Example: NIST_SP-800-53_rev4_catalog.json
#
#   OSCAL XML — NIST OSCAL 1.x catalog schema (XML serialization)
#     Source: https://github.com/usnistgov/oscal-content
#     Example: NIST_SP-800-53_rev5_catalog.xml
#
#   NIST XML (Legacy) — SP 800-53 SCAP feed schema v2.0
#     Source: https://csrc.nist.gov/projects/risk-management/sp800-53-controls/downloads
#     Example: SP_800-53_v5_1_XML.xml
#
# Usage:
#   result = CatalogImportService.call(file_io, original_filename)
#   # => { catalog: <ControlCatalog>, families: 20, controls: 323, updated: 12, created: 311 }
#
# Control ID format: OSCAL canonical `id` is stored as the primary key (e.g., "ac-1", "ac-2.1").
# The OSCAL `props.label` (e.g., "AC-1", "AC-2(1)") is stored in the `label` column for display.
# The OSCAL `props.sort-id` (e.g., "ac-01", "ac-02.01") is stored in the `sort_id` column for ordering.
# Sub-parts (a., 1., (a)) are stored as sibling CatalogControl records under the same family:
#   ac-1, ac-1a, ac-1a.1, ac-1a.1.(a), ac-1a.1.(b), ac-1b, ac-1c, ac-1c.1, ac-1c.2
#
class CatalogImportService
  include ProgressTrackable

  class ImportError < StandardError; end

  FAMILY_NAME_TO_CODE = {
    "ACCESS CONTROL"                              => "AC",
    "AWARENESS AND TRAINING"                      => "AT",
    "AUDIT AND ACCOUNTABILITY"                    => "AU",
    "SECURITY ASSESSMENT AND AUTHORIZATION"       => "CA",
    "ASSESSMENT, AUTHORIZATION, AND MONITORING"  => "CA",
    "CONFIGURATION MANAGEMENT"                   => "CM",
    "CONTINGENCY PLANNING"                        => "CP",
    "IDENTIFICATION AND AUTHENTICATION"           => "IA",
    "INCIDENT RESPONSE"                           => "IR",
    "MAINTENANCE"                                 => "MA",
    "MEDIA PROTECTION"                            => "MP",
    "PHYSICAL AND ENVIRONMENTAL PROTECTION"       => "PE",
    "PLANNING"                                    => "PL",
    "PROGRAM MANAGEMENT"                          => "PM",
    "PERSONNEL SECURITY"                          => "PS",
    "PII PROCESSING AND TRANSPARENCY"             => "PT",
    "PERSONALLY IDENTIFIABLE INFORMATION PROCESSING AND TRANSPARENCY" => "PT",
    "RISK ASSESSMENT"                             => "RA",
    "SYSTEM AND SERVICES ACQUISITION"             => "SA",
    "SYSTEM AND COMMUNICATIONS PROTECTION"        => "SC",
    "SYSTEM AND INFORMATION INTEGRITY"            => "SI",
    "SUPPLY CHAIN RISK MANAGEMENT"                => "SR"
  }.freeze

  def self.call(file_io, original_filename, existing_catalog: nil)
    new(file_io, original_filename, existing_catalog: existing_catalog).call
  end

  def initialize(file_io, original_filename, existing_catalog: nil)
    @content  = file_io.read.force_encoding("UTF-8")
    @filename = original_filename.to_s.downcase
    @existing_catalog = existing_catalog
    @document = existing_catalog  # alias for ProgressTrackable
  end

  def call
    update_processing_stage!(:reading_file, "Detecting catalog format...")

    stats = case detect_format
    when :oscal_json then import_oscal_json
    when :oscal_yaml then import_oscal_yaml
    when :oscal_xml  then import_oscal_xml
    when :nist_xml   then import_nist_xml
    else
      raise ImportError, "Unrecognised format. Upload an OSCAL JSON (.json), OSCAL YAML (.yaml/.yml), OSCAL XML (.xml), or NIST XML (.xml) catalog file."
    end

    # Store content digest for traceability and set catalog as published
    catalog = stats[:catalog]
    digest = Digest::SHA256.hexdigest(@content)
    catalog.update!(catalog_content_digest: digest, lifecycle_status: "published")

    stats
  end

  # ── Format detection ────────────────────────────────────────────────────────

  def detect_format
    if @filename.end_with?(".yaml", ".yml")
      begin
        require "yaml"
        data = YAML.safe_load(@content, permitted_classes: [ Date, Time ])
        return :oscal_yaml if data.is_a?(Hash) && data.dig("catalog", "groups")
      rescue Psych::SyntaxError
        # fall through
      end
    end

    if @filename.end_with?(".json")
      begin
        data = JSON.parse(@content)
        return :oscal_json if data.dig("catalog", "groups")
      rescue JSON::ParserError
        # fall through
      end
    end

    if @filename.end_with?(".xml")
      # OSCAL XML: <catalog> root element with OSCAL namespace or <group> children
      return :oscal_xml if @content.include?("csrc.nist.gov/ns/oscal") ||
                           (@content.include?("<catalog") && @content.include?("<group"))
      # Legacy SCAP feed: <controls:control> elements
      return :nist_xml if @content.include?("<controls:control>")
    end

    # Content-sniff as fallback
    if @content.lstrip.start_with?("{")
      begin
        data = JSON.parse(@content)
        return :oscal_json if data.dig("catalog", "groups")
      rescue JSON::ParserError
        # fall through
      end
    end

    return :nist_xml if @content.include?("<controls:control>")

    :unknown
  end

  # ── OSCAL YAML import ───────────────────────────────────────────────────────
  #
  # OSCAL YAML has the same structure as OSCAL JSON (just a different
  # serialization). Parse to a Ruby hash, convert to JSON, and delegate.
  #
  def import_oscal_yaml
    update_processing_stage!(:parsing, "Parsing OSCAL YAML catalog...")

    require "yaml"
    data = YAML.safe_load(@content, permitted_classes: [ Date, Time ])
    raise ImportError, "Not a valid OSCAL YAML catalog — missing 'catalog.groups'." unless data.is_a?(Hash) && data.dig("catalog", "groups")

    @content = JSON.generate(data)
    @import_format_override = "oscal_yaml"
    import_oscal_json
  end

  # ── OSCAL JSON import ───────────────────────────────────────────────────────
  #
  # Structure:
  #   catalog.metadata.title   → catalog name
  #   catalog.metadata.version → version
  #   catalog.groups[]         → families (id=code, title=name)
  #     .controls[]            → controls
  #       .props[name=label]   → display ID  (e.g. "AC-1" → stored as "AC-01")
  #       .props[name=priority]→ priority    (e.g. "P1")
  #       .parts[name=statement]
  #         .parts[name=item]  → sub-parts (AC-01a, AC-01a.1, AC-01a.1.(a) …)
  #       .parts[name=guidance]  .prose      → supplemental guidance
  #         .links[rel=related]              → related control IDs
  #
  def import_oscal_json
    update_processing_stage!(:parsing, "Parsing OSCAL JSON catalog...")

    data        = JSON.parse(@content)
    cat_data    = data.fetch("catalog") { raise ImportError, "Missing 'catalog' key — not a valid OSCAL catalog JSON." }
    metadata    = cat_data.fetch("metadata", {})
    groups      = cat_data.fetch("groups") { raise ImportError, "No 'groups' found in catalog." }

    catalog_name  = metadata["title"].presence || File.basename(@filename, ".json").titleize
    version       = metadata["version"].presence || metadata["last-modified"]&.first(10)
    oscal_version = metadata["oscal-version"]
    published     = metadata["published"]
    metadata_extra = metadata.slice(*OscalMetadata::METADATA_EXTRA_KEYS)

    # Preserve the catalog's OSCAL document UUID and back-matter resources for
    # cross-referencing when profiles are imported later.
    metadata_extra["catalog_uuid"] = cat_data["uuid"] if cat_data["uuid"].present?
    metadata_extra["import_format"] = @import_format_override || "oscal_json"
    back_matter_resources = cat_data.dig("back-matter", "resources")
    metadata_extra["back_matter_resources"] = back_matter_resources if back_matter_resources.present?

    catalog = if @existing_catalog
      attrs = { name: catalog_name, version: version, source: "OSCAL" }
      attrs[:oscal_version] = oscal_version.presence || @existing_catalog.oscal_version
      attrs[:published] = published.presence || @existing_catalog.published
      attrs[:metadata_extra] = metadata_extra.present? ? metadata_extra : @existing_catalog.metadata_extra
      attrs[:oscal_uuid] = metadata_extra["catalog_uuid"] if metadata_extra["catalog_uuid"].present?
      @existing_catalog.update!(attrs)
      @existing_catalog
    else
      upsert_catalog(catalog_name, version, "OSCAL",
                     oscal_version: oscal_version, published: published,
                     metadata_extra: metadata_extra)
    end
    stats   = { catalog: catalog, families: 0, controls: 0, created: 0, updated: 0 }

    update_processing_stage!(:creating_records, "Importing #{groups.size} control families...")

    groups.each_with_index do |group, idx|
      family_code = group["id"].to_s.upcase
      family_name = group["title"].to_s.strip
      next if family_code.blank?

      family = upsert_family(catalog, family_code, family_name, idx + 1)
      stats[:families] += 1

      (group["controls"] || []).each do |ctrl|
        result = import_oscal_control(family, ctrl)
        stats[:controls] += 1
        stats[result]    += 1
      end
    end

    stats
  end

  def import_oscal_control(family, ctrl)
    # Store the OSCAL canonical id as the primary key for cross-referencing.
    # The label prop is stored separately for display; sort-id for ordering.
    control_id = ctrl["id"].to_s.strip                         # "ac-1", "ac-2.1"
    ctrl_label = oscal_prop(ctrl["props"], "label")            # "AC-1", "AC-2(1)"
    sort_id    = oscal_prop(ctrl["props"], "sort-id")          # "ac-01", "ac-02.01"
    title      = ctrl["title"].to_s.strip
    priority   = oscal_prop(ctrl["props"], "priority")
    baselines  = oscal_prop_all(ctrl["props"], "impact-level")
    baseline   = baselines.join(", ").presence

    # Statement: collect prose from all statement/item parts recursively (for the parent record)
    statement = oscal_collect_prose(ctrl["parts"], names: %w[statement item])

    # Guidance part
    guidance_part = (ctrl["parts"] || []).find { |p| p["name"] == "guidance" }
    supplemental  = guidance_part&.dig("prose").to_s.strip.presence

    # Related controls from guidance part links
    related = (guidance_part&.dig("links") || [])
              .select { |l| l["rel"] == "related" }
              .map    { |l| l["href"]&.delete("#") }
              .compact
              .join(", ")

    # Assessment parts (EXAMINE, INTERVIEW, TEST methods with objects prose)
    assessment_parts = (ctrl["parts"] || []).select { |p| p["name"] == "assessment" }
    assessment_data = assessment_parts.map do |ap|
      method = (ap["props"] || []).find { |pr| pr["name"] == "method" }&.dig("value")
      objects = (ap["parts"] || []).find { |pp| pp["name"] == "objects" }&.dig("prose")
      { "method" => method, "objects" => objects }.compact
    end.reject(&:empty?)

    guidance_data = {
      "statement"             => statement,
      "supplemental_guidance" => supplemental,
      "related_controls"      => related.presence,
      "assessment"            => assessment_data.presence
    }.compact.reject { |_, v| v.blank? }

    # Parameter definitions (Assignment/Selection placeholders for profiles to resolve)
    params_data = ctrl["params"].presence || []

    result = upsert_catalog_control(family, control_id, title, priority, baseline, guidance_data,
                                    params_data: params_data, label: ctrl_label, sort_id: sort_id)

    # Create sub-control records for each statement item part (a., 1., (a), …)
    stmt_part = (ctrl["parts"] || []).find { |p| p["name"] == "statement" }
    import_oscal_item_parts(family, control_id, stmt_part&.[]("parts"))

    # Recurse into enhancements (sub-controls like AC-1(1), AC-1(2))
    (ctrl["controls"] || []).each do |sub|
      import_oscal_control(family, sub)
    end

    result
  end

  # Recursively create CatalogControl records for OSCAL statement item parts.
  # Each item part becomes a sibling record with a hierarchical ID suffix:
  #   parent "ac-1" + label "a." → "ac-1a"
  #   parent "ac-1a" + label "1." → "ac-1a.1"
  #   parent "ac-1a.1" + label "(a)" → "ac-1a.1.(a)"
  def import_oscal_item_parts(family, parent_id, parts)
    return if parts.blank?
    parts.each do |part|
      next unless part["name"] == "item"
      label = oscal_prop(part["props"], "label").to_s.strip
      next if label.blank?

      sub_id = parent_id + label_to_suffix(label)
      prose  = part["prose"].to_s.strip

      # Use the prose text as the title (truncated for readability) instead of
      # the raw label ("a.", "1.") which is meaningless as a title.
      title = prose.present? ? prose.truncate(200) : label

      upsert_catalog_control(family, sub_id, title, nil, nil,
        prose.present? ? { "statement" => prose } : {})

      # Recurse into nested item parts
      import_oscal_item_parts(family, sub_id, part["parts"])
    end
  end

  # ── OSCAL XML import ────────────────────────────────────────────────────────
  #
  # Structure (identical to OSCAL JSON but in XML serialization):
  #   <catalog uuid="…">
  #     <metadata><title>…</title><version>…</version><oscal-version>…</oscal-version></metadata>
  #     <group id="ac" class="family">
  #       <title>Access Control</title>
  #       <control id="ac-1">
  #         <title>Policy and Procedures</title>
  #         <param id="ac-01_odp.03">
  #           <select how-many="one-or-more"><choice>…</choice></select>
  #         </param>
  #         <prop name="label" value="AC-1"/>
  #         <prop name="sort-id" value="ac-01"/>
  #         <part name="statement"><part name="item">…</part></part>
  #         <part name="guidance"><p>…</p></part>
  #         <control id="ac-1.1">…</control>  ← enhancements
  #
  def import_oscal_xml
    update_processing_stage!(:parsing, "Parsing OSCAL XML catalog...")

    require "nokogiri"
    doc = Nokogiri::XML(@content) { |c| c.strict.noblanks }
    doc.remove_namespaces!

    catalog_node = doc.at_xpath("//catalog")
    raise ImportError, "No <catalog> element found — not a valid OSCAL XML catalog." unless catalog_node

    metadata_node = catalog_node.at_xpath("metadata")
    groups        = catalog_node.xpath("group")
    raise ImportError, "No <group> elements found in catalog." if groups.empty?

    catalog_name  = metadata_node&.at_xpath("title")&.text.to_s.strip.presence ||
                    File.basename(@filename, ".xml").titleize
    version       = metadata_node&.at_xpath("version")&.text.to_s.strip.presence ||
                    metadata_node&.at_xpath("last-modified")&.text.to_s.first(10)
    oscal_version = metadata_node&.at_xpath("oscal-version")&.text.to_s.strip.presence
    published     = metadata_node&.at_xpath("published")&.text.to_s.strip.presence

    # Collect metadata extras (props, links, roles, parties, etc.)
    metadata_extra = {}
    metadata_extra["catalog_uuid"] = catalog_node["uuid"] if catalog_node["uuid"].present?
    metadata_extra["import_format"] = "oscal_xml"

    back_matter = catalog_node.at_xpath("back-matter")
    if back_matter
      resources = back_matter.xpath("resource").map do |r|
        res = { "uuid" => r["uuid"] }
        title_node = r.at_xpath("title")
        res["title"] = title_node.text.strip if title_node
        r.xpath("rlink").each do |rl|
          res["rlinks"] ||= []
          res["rlinks"] << { "href" => rl["href"], "media-type" => rl["media-type"] }.compact
        end
        res
      end
      metadata_extra["back_matter_resources"] = resources if resources.any?
    end

    catalog = if @existing_catalog
      attrs = { name: catalog_name, version: version, source: "OSCAL" }
      attrs[:oscal_version] = oscal_version.presence || @existing_catalog.oscal_version
      attrs[:published] = published.presence || @existing_catalog.published
      attrs[:metadata_extra] = metadata_extra.present? ? metadata_extra : @existing_catalog.metadata_extra
      attrs[:oscal_uuid] = metadata_extra["catalog_uuid"] if metadata_extra["catalog_uuid"].present?
      @existing_catalog.update!(attrs)
      @existing_catalog
    else
      upsert_catalog(catalog_name, version, "OSCAL",
                     oscal_version: oscal_version, published: published,
                     metadata_extra: metadata_extra)
    end
    stats = { catalog: catalog, families: 0, controls: 0, created: 0, updated: 0 }

    groups.each_with_index do |group, idx|
      family_code = group["id"].to_s.upcase
      family_name = group.at_xpath("title")&.text.to_s.strip
      next if family_code.blank?

      family = upsert_family(catalog, family_code, family_name, idx + 1)
      stats[:families] += 1

      group.xpath("control").each do |ctrl_node|
        import_oscal_xml_control(family, ctrl_node, stats)
      end
    end

    stats
  end

  def import_oscal_xml_control(family, ctrl_node, stats)
    control_id = ctrl_node["id"].to_s.strip
    ctrl_label = oscal_xml_prop(ctrl_node, "label")
    sort_id    = oscal_xml_prop(ctrl_node, "sort-id")
    title      = ctrl_node.at_xpath("title")&.text.to_s.strip
    priority   = oscal_xml_prop(ctrl_node, "priority")
    baselines  = oscal_xml_prop_all(ctrl_node, "impact-level")
    baseline   = baselines.join(", ").presence

    # Statement prose
    statement = oscal_xml_collect_prose(ctrl_node.xpath("part").select { |p| p["name"] == "statement" })

    # Guidance part
    guidance_node = ctrl_node.xpath("part").find { |p| p["name"] == "guidance" }
    supplemental  = guidance_node ? xml_text_content(guidance_node).strip.presence : nil

    # Related controls from guidance links
    related = if guidance_node
      guidance_node.xpath("link").select { |l| l["rel"] == "related" }
                   .map { |l| l["href"]&.delete("#") }
                   .compact.join(", ").presence
    end

    guidance_data = {
      "statement"             => statement,
      "supplemental_guidance" => supplemental,
      "related_controls"      => related
    }.compact.reject { |_, v| v.blank? }

    # Parameter definitions — the key addition for issue #162
    params_data = oscal_xml_collect_params(ctrl_node)

    result = upsert_catalog_control(family, control_id, title, priority, baseline, guidance_data,
                                    params_data: params_data, label: ctrl_label, sort_id: sort_id)
    stats[:controls] += 1
    stats[result]    += 1

    # Sub-control records for statement item parts
    stmt_parts = ctrl_node.xpath("part").select { |p| p["name"] == "statement" }
    stmt_parts.each do |stmt|
      import_oscal_xml_item_parts(family, control_id, stmt.xpath("part"))
    end

    # Recurse into enhancements (nested <control> elements)
    ctrl_node.xpath("control").each do |sub|
      import_oscal_xml_control(family, sub, stats)
    end
  end

  # Recursively create CatalogControl records for OSCAL XML statement item parts.
  def import_oscal_xml_item_parts(family, parent_id, parts)
    return if parts.nil? || parts.empty?
    parts.each do |part|
      next unless part["name"] == "item"
      label = oscal_xml_prop(part, "label").to_s.strip
      next if label.blank?

      sub_id = parent_id + label_to_suffix(label)
      prose  = xml_prose_with_inserts(part.at_xpath("p")).presence ||
               xml_text_content(part).strip.presence

      title = prose.present? ? prose.truncate(200) : label

      upsert_catalog_control(family, sub_id, title, nil, nil,
        prose.present? ? { "statement" => prose } : {})

      # Recurse into nested item parts
      import_oscal_xml_item_parts(family, sub_id, part.xpath("part"))
    end
  end

  # ── OSCAL XML helpers ──────────────────────────────────────────────────────

  # Extract a <prop> value by name from direct children of a node.
  def oscal_xml_prop(node, name)
    node.xpath("prop").find { |p| p["name"] == name }&.[]("value")
  end

  # Extract all <prop> values matching a name.
  def oscal_xml_prop_all(node, name)
    node.xpath("prop").select { |p| p["name"] == name }.map { |p| p["value"] }.compact
  end

  # Collect all <param> children from a control node into the OSCAL JSON-equivalent structure.
  def oscal_xml_collect_params(ctrl_node)
    ctrl_node.xpath("param").map do |param_node|
      entry = { "id" => param_node["id"] }

      # Props (label, alt-identifier, etc.)
      props = param_node.xpath("prop").map do |p|
        h = { "name" => p["name"], "value" => p["value"] }
        h["class"] = p["class"] if p["class"]
        h["ns"] = p["ns"] if p["ns"]
        h
      end
      entry["props"] = props if props.any?

      # Label
      label_node = param_node.at_xpath("label")
      entry["label"] = label_node.text.strip if label_node

      # Select with choices
      select_node = param_node.at_xpath("select")
      if select_node
        sel = {}
        sel["how-many"] = select_node["how-many"] if select_node["how-many"]
        sel["choice"] = select_node.xpath("choice").map { |c| c.text.strip }
        entry["select"] = sel
      end

      # Guidelines
      guidelines = param_node.xpath("guideline").map do |g|
        { "prose" => xml_text_content(g) }
      end
      entry["guidelines"] = guidelines if guidelines.any?

      entry
    end
  end

  # Recursively collect prose from OSCAL XML <part> elements matching statement/item names.
  def oscal_xml_collect_prose(parts, depth: 0)
    return "" if parts.nil? || parts.empty?
    lines = []
    parts.each do |part|
      next unless %w[statement item].include?(part["name"])
      label = oscal_xml_prop(part, "label")
      prose = xml_prose_with_inserts(part.at_xpath("p"))
      line  = [ label, prose ].select(&:present?).join(" ")
      lines << ("  " * depth + line) if line.present?
      lines << oscal_xml_collect_prose(part.xpath("part"), depth: depth + 1)
    end
    lines.reject(&:blank?).join("\n")
  end

  # ── NIST XML import (Legacy SCAP feed) ─────────────────────────────────────
  #
  # Structure (SCAP SP800-53 feed v2.0):
  #   <controls:control>
  #     <family>ACCESS CONTROL</family>
  #     <number>AC-1</number>  → stored as "ac-1" (canonical OSCAL format)
  #     <title>POLICY AND PROCEDURES</title>
  #     <baseline>LOW</baseline>
  #     <statement>
  #       <description>…</description>
  #       <statement><number>a.</number><description>…</description>
  #         <statement><number>1.</number>…</statement>
  #       </statement>
  #     </statement>
  #     <discussion><description><p>…</p></description></discussion>
  #     <related>IA-1</related>
  #     <references><reference><short_name>…</short_name></reference>
  #
  def import_nist_xml
    update_processing_stage!(:parsing, "Parsing NIST XML catalog...")

    require "nokogiri"
    doc = Nokogiri::XML(@content) { |c| c.strict.noblanks }
    doc.remove_namespaces!

    controls = doc.xpath("//control")
    raise ImportError, "No <control> elements found — not a valid NIST SP 800-53 XML feed." if controls.empty?

    # Infer catalog name from pub_date attribute or filename
    pub_date     = doc.root&.[]("pub_date")
    catalog_name = xml_catalog_name(controls.first, pub_date)
    version      = pub_date.presence || File.basename(@filename, ".xml")

    metadata_extra = { "import_format" => "nist_xml" }
    catalog = if @existing_catalog
      @existing_catalog.update!(metadata_extra: @existing_catalog.metadata_extra.merge(metadata_extra))
      @existing_catalog
    else
      upsert_catalog(catalog_name, version, "NIST XML", metadata_extra: metadata_extra)
    end
    stats = { catalog: catalog, families: 0, controls: 0, created: 0, updated: 0 }

    # Group by family; build families on the fly
    family_cache = {}
    sort_counter = {}

    controls.each do |ctrl_node|
      family_full = ctrl_node.at_xpath("family")&.text.to_s.strip.upcase
      number      = ctrl_node.at_xpath("number")&.text.to_s.strip
      next if number.blank?

      family_code = xml_family_code(family_full, number)
      next if family_code.blank?

      # Friendly title-case name
      family_name = (FAMILY_NAME_TO_CODE.key(family_code) || family_full).titleize

      unless family_cache.key?(family_code)
        sort_counter[family_code] ||= sort_counter.size + 1
        family_cache[family_code] = upsert_family(catalog, family_code, family_name, sort_counter[family_code])
        stats[:families] += 1
      end

      family = family_cache[family_code]
      import_xml_control(family, ctrl_node, stats)
    end

    stats
  end

  def import_xml_control(family, ctrl_node, stats)
    raw_number  = ctrl_node.at_xpath("number")&.text.to_s.strip  # "AC-1"
    control_id  = raw_number.downcase                              # "ac-1" (canonical OSCAL format)
    ctrl_label  = raw_number                                       # "AC-1" (display)
    sort_id     = pad_control_id(raw_number).downcase              # "ac-01" (ordering)
    title       = ctrl_node.at_xpath("title")&.text.to_s.strip.titleize
    baselines   = ctrl_node.xpath("baseline").map(&:text).map(&:strip).reject(&:blank?)
    baseline    = baselines.join(", ").presence

    # Build statement text from nested structure (for the parent record)
    root_stmt = ctrl_node.at_xpath("statement")
    statement = root_stmt ? xml_collect_statement(root_stmt) : nil

    # Supplemental guidance from <discussion>
    discussion = ctrl_node.at_xpath("discussion/description")
    supplemental = discussion ? xml_text_content(discussion).strip.presence : nil

    # Related controls
    related = ctrl_node.xpath("related").map(&:text).map(&:strip).reject(&:blank?).join(", ").presence

    # References
    nist_refs = ctrl_node.xpath("references/reference/short_name").map(&:text).map(&:strip).reject(&:blank?).join(", ").presence

    guidance_data = {
      "statement"             => statement,
      "supplemental_guidance" => supplemental,
      "related_controls"      => related,
      "nist_references"       => nist_refs
    }.compact.reject { |_, v| v.blank? }

    result = upsert_catalog_control(family, control_id, title, nil, baseline, guidance_data,
                                    label: ctrl_label, sort_id: sort_id)
    stats[:controls] += 1
    stats[result]    += 1

    # Create sub-control records from nested <statement> elements
    import_xml_item_parts(family, control_id, root_stmt) if root_stmt

    # Import control enhancements (e.g., AC-2(1), AC-2(2))
    ctrl_node.xpath("control-enhancement").each do |enh_node|
      import_xml_enhancement(family, enh_node, stats)
    end
  end

  # Import a NIST XML <control-enhancement> element.
  # Converts enhancement numbering to OSCAL canonical format:
  #   "AC-2(1)" → "ac-2.1", "AC-2(13)" → "ac-2.13"
  def import_xml_enhancement(family, enh_node, stats)
    raw_number = enh_node.at_xpath("number")&.text.to_s.strip  # "AC-2(1)"
    return if raw_number.blank?

    control_id = nist_enhancement_to_oscal_id(raw_number)         # "ac-2.1"
    ctrl_label = raw_number                                        # "AC-2(1)" (display)
    sort_id    = pad_enhancement_id(raw_number).downcase           # "ac-02.01" (ordering)
    title      = enh_node.at_xpath("title")&.text.to_s.strip.titleize
    baselines  = enh_node.xpath("baseline").map(&:text).map(&:strip).reject(&:blank?)
    baseline   = baselines.join(", ").presence

    root_stmt    = enh_node.at_xpath("statement")
    statement    = root_stmt ? xml_collect_statement(root_stmt) : nil
    discussion   = enh_node.at_xpath("discussion/description")
    supplemental = discussion ? xml_text_content(discussion).strip.presence : nil
    related      = enh_node.xpath("related").map(&:text).map(&:strip).reject(&:blank?).join(", ").presence

    guidance_data = {
      "statement"             => statement,
      "supplemental_guidance" => supplemental,
      "related_controls"      => related
    }.compact.reject { |_, v| v.blank? }

    result = upsert_catalog_control(family, control_id, title, nil, baseline, guidance_data,
                                    label: ctrl_label, sort_id: sort_id)
    stats[:controls] += 1
    stats[result]    += 1

    # Enhancement sub-parts from nested <statement> elements
    import_xml_item_parts(family, control_id, root_stmt) if root_stmt
  end

  # Recursively create CatalogControl records for XML nested statement elements.
  #
  # The NIST XML <number> contains the FULL control sub-ID (not just a label suffix):
  #   "AC-1a."       → sub_id "ac-1a"     (label: "AC-1a")
  #   "AC-1a.1."     → sub_id "ac-1a.1"   (label: "AC-1a.1")
  #   "AC-1a.1.(a)"  → sub_id "ac-1a.1.(a)" (label: "AC-1a.1.(a)")
  #
  # We strip the trailing dot and lowercase for canonical format.
  def import_xml_item_parts(family, _parent_id, stmt_node)
    return if stmt_node.nil?
    stmt_node.xpath("statement").each do |child|
      number = child.at_xpath("number")&.text.to_s.strip
      next if number.blank?

      raw    = number.chomp(".")          # "AC-1a" (strip trailing dot)
      sub_id = raw.downcase               # "ac-1a" (canonical)
      label  = raw                        # "AC-1a" (display)
      next if sub_id.blank?

      desc   = child.at_xpath("description")
      prose  = desc ? xml_text_content(desc).strip.presence : nil

      # Use prose text as the title (truncated) instead of the raw label
      title = prose.present? ? prose.truncate(200) : label

      upsert_catalog_control(family, sub_id, title, nil, nil,
        prose ? { "statement" => prose } : {},
        label: label)

      # Recurse into deeper nesting
      import_xml_item_parts(family, sub_id, child)
    end
  end

  # ── Shared DB upsert helpers ─────────────────────────────────────────────────

  def upsert_catalog(name, version, source, oscal_version: nil, published: nil, metadata_extra: {})
    catalog = ControlCatalog.find_or_initialize_by(name: name)
    attrs = { version: version, source: source }
    attrs[:oscal_version] = oscal_version if oscal_version.present?
    attrs[:published] = published if published.present?
    attrs[:metadata_extra] = metadata_extra if metadata_extra.present?
    # Set oscal_uuid from the imported catalog's UUID if available
    if metadata_extra["catalog_uuid"].present?
      attrs[:oscal_uuid] = metadata_extra["catalog_uuid"]
    end
    catalog.assign_attributes(attrs)
    catalog.save!
    catalog
  end

  def upsert_family(catalog, code, name, sort_order)
    family = catalog.control_families.find_or_initialize_by(code: code)
    family.assign_attributes(name: name, sort_order: sort_order)
    family.save!
    family
  end

  def upsert_catalog_control(family, control_id, title, priority, baseline, guidance_data, params_data: [], label: nil, sort_id: nil)
    ctrl = family.catalog_controls.find_or_initialize_by(control_id: control_id)
    is_new = ctrl.new_record?
    attrs = {
      title:            title.presence || ctrl.title,
      priority:         priority.presence || ctrl.priority,
      baseline_impact:  baseline.presence || ctrl.baseline_impact,
      guidance_data:    guidance_data.any? ? guidance_data : (ctrl.guidance_data || {})
    }
    attrs[:params_data] = params_data if params_data.present?
    attrs[:label] = label if label.present?
    attrs[:sort_id] = sort_id if sort_id.present?
    ctrl.assign_attributes(attrs)
    ctrl.save!
    is_new ? :created : :updated
  end

  # ── ID helpers ───────────────────────────────────────────────────────────────

  # Zero-pad single-digit control numbers: "AC-1" → "AC-01", "AC-10" unchanged.
  # Only the base number segment is padded; sub-part suffixes are unaffected.
  def pad_control_id(id)
    id.to_s.sub(/\A([A-Z]+-?)(\d+)\z/) { "#{$1}#{$2.rjust(2, '0')}" }
  end

  # Convert an OSCAL/XML statement label into an ID suffix for the parent control:
  #   "a."  → "a"    (letter — appended directly: "ac-1" + "a" = "ac-1a")
  #   "1."  → ".1"   (digit  — dot separator:     "ac-1a" + ".1" = "ac-1a.1")
  #   "(a)" → ".(a)" (paren  — dot separator:     "ac-1a.1" + ".(a)" = "ac-1a.1.(a)")
  def label_to_suffix(label)
    l = label.strip
    case l
    when /\A([a-z])\.\z/    then $1          # "a." → "a"
    when /\A(\d+)\.\z/      then ".#{$1}"    # "1." → ".1"
    when /\A\([^)]+\)\z/    then ".#{l}"     # "(a)" → ".(a)"
    else ".#{l.chomp('.')}"                  # fallback
    end
  end

  # Convert NIST XML enhancement numbering to OSCAL canonical format:
  #   "AC-2(1)"  → "ac-2.1"
  #   "AC-2(13)" → "ac-2.13"
  def nist_enhancement_to_oscal_id(raw)
    raw.downcase.gsub(/\((\d+)\)/, '.\1')
  end

  # Zero-pad enhancement IDs for sort ordering:
  #   "AC-2(1)"  → "AC-02.01"
  #   "AC-2(13)" → "AC-02.13"
  def pad_enhancement_id(raw)
    raw.sub(/\A([A-Z]+-?)(\d+)\((\d+)\)\z/) { "#{$1}#{$2.rjust(2, '0')}.#{$3.rjust(2, '0')}" }
  end

  # ── OSCAL helpers ────────────────────────────────────────────────────────────

  def oscal_prop(props, name)
    (props || []).find { |p| p["name"] == name }&.dig("value")
  end

  def oscal_prop_all(props, name)
    (props || []).select { |p| p["name"] == name }.map { |p| p["value"] }.compact
  end

  # Recursively collect prose from parts matching given names, with label prefixes.
  def oscal_collect_prose(parts, names: %w[statement item], depth: 0)
    return "" if parts.blank?
    lines = []
    parts.each do |part|
      next unless names.include?(part["name"])
      label = oscal_prop(part["props"], "label")
      prose = part["prose"].to_s.strip
      line  = [ label, prose ].select(&:present?).join(" ")
      lines << ("  " * depth + line) if line.present?
      lines << oscal_collect_prose(part["parts"], names: names, depth: depth + 1)
    end
    lines.reject(&:blank?).join("\n")
  end

  # ── NIST XML helpers ─────────────────────────────────────────────────────────

  def xml_family_code(family_full, control_number)
    # Prefer FAMILY_NAME_TO_CODE lookup
    return FAMILY_NAME_TO_CODE[family_full] if FAMILY_NAME_TO_CODE.key?(family_full)
    # Fall back to the prefix of the control number (e.g. "AC-1" → "AC")
    control_number.to_s.split("-").first.upcase.presence
  end

  def xml_catalog_name(first_ctrl_node, pub_date)
    family = first_ctrl_node&.at_xpath("family")&.text.to_s
    if family.include?("800-53") || @filename.include?("800-53")
      rev = @filename.match(/rev\s*(\d+)/i)&.captures&.first ||
            @filename.match(/v(\d+)/i)&.captures&.first
      "NIST SP 800-53#{rev ? " Rev #{rev}" : ""} (XML import)"
    else
      "Imported Catalog#{pub_date ? " (#{pub_date})" : ""}"
    end
  end

  # Recursively collect <number> + <description> text from nested <statement> nodes.
  def xml_collect_statement(node, depth = 0)
    lines = []
    desc = node.at_xpath("description")
    text = desc ? xml_text_content(desc).strip : nil
    num  = node.at_xpath("number")&.text&.strip

    line = [ num, text ].select(&:present?).join(" ")
    lines << ("  " * depth + line) if line.present?

    node.xpath("statement").each do |child|
      lines << xml_collect_statement(child, depth + 1)
    end

    lines.reject(&:blank?).join("\n")
  end

  # Extract plain text from a Nokogiri node (strips HTML/inline tags like <p>, <i>).
  def xml_text_content(node)
    node.xpath(".//text()").map(&:text).join(" ").gsub(/\s+/, " ").strip
  end

  # Extract text from a <p> element, converting <insert type="param" id-ref="..."/>
  # into {{ insert: param, ... }} template markup so parameter references are preserved.
  def xml_prose_with_inserts(p_node)
    return "" if p_node.nil?
    p_node.children.map do |child|
      if child.element? && child.name == "insert" && child["type"] == "param"
        "{{ insert: param, #{child['id-ref']} }}"
      else
        child.text
      end
    end.join.gsub(/\s+/, " ").strip
  end
end
