# CatalogImportService
#
# Imports control catalogs from two supported formats:
#
#   OSCAL JSON — NIST OSCAL 1.x catalog schema
#     Source: https://github.com/usnistgov/oscal-content
#     Example: NIST_SP-800-53_rev4_catalog.json
#
#   NIST XML — SP 800-53 SCAP feed schema v2.0
#     Source: https://csrc.nist.gov/projects/risk-management/sp800-53-controls/downloads
#     Example: SP_800-53_v5_1_XML.xml
#
# Usage:
#   result = CatalogImportService.call(file_io, original_filename)
#   # => { catalog: <ControlCatalog>, families: 20, controls: 323, updated: 12, created: 311 }
#
# Control ID format: single-digit numbers are zero-padded (AC-1 → AC-01, AC-10 unchanged).
# Sub-parts (a., 1., (a)) are stored as sibling CatalogControl records under the same family:
#   AC-01, AC-01a, AC-01a.1, AC-01a.1.(a), AC-01a.1.(b), AC-01b, AC-01c, AC-01c.1, AC-01c.2
#
class CatalogImportService
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

  def self.call(file_io, original_filename)
    new(file_io, original_filename).call
  end

  def initialize(file_io, original_filename)
    @content  = file_io.read.force_encoding("UTF-8")
    @filename = original_filename.to_s.downcase
  end

  def call
    case detect_format
    when :oscal_json then import_oscal_json
    when :nist_xml   then import_nist_xml
    else
      raise ImportError, "Unrecognised format. Upload an OSCAL JSON (.json) or NIST XML (.xml) catalog file."
    end
  end

  # ── Format detection ────────────────────────────────────────────────────────

  def detect_format
    if @filename.end_with?(".json")
      begin
        data = JSON.parse(@content)
        return :oscal_json if data.dig("catalog", "groups")
      rescue JSON::ParserError
        # fall through
      end
    end

    if @filename.end_with?(".xml")
      return :nist_xml if @content.include?("sp800-53") || @content.include?("<controls:control>")
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
    back_matter_resources = cat_data.dig("back-matter", "resources")
    metadata_extra["back_matter_resources"] = back_matter_resources if back_matter_resources.present?

    catalog = upsert_catalog(catalog_name, version, "OSCAL",
                             oscal_version: oscal_version, published: published,
                             metadata_extra: metadata_extra)
    stats   = { catalog: catalog, families: 0, controls: 0, created: 0, updated: 0 }

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
    label       = oscal_prop(ctrl["props"], "label")
    raw_id      = label.presence || ctrl["id"].to_s.upcase.tr("-", "-")
    control_id  = pad_control_id(raw_id)
    title       = ctrl["title"].to_s.strip
    priority    = oscal_prop(ctrl["props"], "priority")
    baselines   = oscal_prop_all(ctrl["props"], "impact-level")
    baseline    = baselines.join(", ").presence

    # Statement: collect prose from all statement/item parts recursively (for the parent record)
    statement = oscal_collect_prose(ctrl["parts"], names: %w[statement item])

    # Guidance part
    guidance_part = (ctrl["parts"] || []).find { |p| p["name"] == "guidance" }
    supplemental  = guidance_part&.dig("prose").to_s.strip.presence

    # Related controls from guidance part links
    related = (guidance_part&.dig("links") || [])
              .select { |l| l["rel"] == "related" }
              .map    { |l| l["href"]&.delete("#")&.upcase }
              .compact
              .join(", ")

    guidance_data = {
      "statement"             => statement,
      "supplemental_guidance" => supplemental,
      "related_controls"      => related.presence
    }.compact.reject { |_, v| v.blank? }

    # Parameter definitions (Assignment/Selection placeholders for profiles to resolve)
    params_data = ctrl["params"].presence || []

    result = upsert_catalog_control(family, control_id, title, priority, baseline, guidance_data, params_data: params_data)

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
  #   parent "AC-01" + label "a." → "AC-01a"
  #   parent "AC-01a" + label "1." → "AC-01a.1"
  #   parent "AC-01a.1" + label "(a)" → "AC-01a.1.(a)"
  def import_oscal_item_parts(family, parent_id, parts)
    return if parts.blank?
    parts.each do |part|
      next unless part["name"] == "item"
      label = oscal_prop(part["props"], "label").to_s.strip
      next if label.blank?

      sub_id = parent_id + label_to_suffix(label)
      prose  = part["prose"].to_s.strip

      upsert_catalog_control(family, sub_id, label, nil, nil,
        prose.present? ? { "statement" => prose } : {})

      # Recurse into nested item parts
      import_oscal_item_parts(family, sub_id, part["parts"])
    end
  end

  # ── NIST XML import ─────────────────────────────────────────────────────────
  #
  # Structure (SCAP SP800-53 feed v2.0):
  #   <controls:control>
  #     <family>ACCESS CONTROL</family>
  #     <number>AC-1</number>  → stored as "AC-01"
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
    require "nokogiri"
    doc = Nokogiri::XML(@content) { |c| c.strict.noblanks }
    doc.remove_namespaces!

    controls = doc.xpath("//control")
    raise ImportError, "No <control> elements found — not a valid NIST SP 800-53 XML feed." if controls.empty?

    # Infer catalog name from pub_date attribute or filename
    pub_date     = doc.root&.[]("pub_date")
    catalog_name = xml_catalog_name(controls.first, pub_date)
    version      = pub_date.presence || File.basename(@filename, ".xml")

    catalog = upsert_catalog(catalog_name, version, "NIST XML")
    stats   = { catalog: catalog, families: 0, controls: 0, created: 0, updated: 0 }

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
      result = import_xml_control(family, ctrl_node)
      stats[:controls] += 1
      stats[result]    += 1
    end

    stats
  end

  def import_xml_control(family, ctrl_node)
    control_id  = pad_control_id(ctrl_node.at_xpath("number")&.text.to_s.strip)
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

    result = upsert_catalog_control(family, control_id, title, nil, baseline, guidance_data)

    # Create sub-control records from nested <statement> elements
    import_xml_item_parts(family, control_id, root_stmt) if root_stmt

    result
  end

  # Recursively create CatalogControl records for XML nested statement elements.
  #
  # The NIST XML <number> contains the FULL control sub-ID (not just a label suffix):
  #   "AC-1a."       → sub_id "AC-01a"
  #   "AC-1a.1."     → sub_id "AC-01a.1"
  #   "AC-1a.1.(a)"  → sub_id "AC-01a.1.(a)"
  #
  # We strip the trailing dot and zero-pad the base number.
  def import_xml_item_parts(family, _parent_id, stmt_node)
    return if stmt_node.nil?
    stmt_node.xpath("statement").each do |child|
      number = child.at_xpath("number")&.text.to_s.strip
      next if number.blank?

      # Build canonical ID: strip trailing "." then zero-pad first number segment
      sub_id = number.chomp(".").sub(/\A([A-Z]+-?)(\d+)/) { "#{$1}#{$2.rjust(2, '0')}" }
      next if sub_id.blank?

      desc   = child.at_xpath("description")
      prose  = desc ? xml_text_content(desc).strip.presence : nil

      upsert_catalog_control(family, sub_id, number.chomp("."), nil, nil,
        prose ? { "statement" => prose } : {})

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

  def upsert_catalog_control(family, control_id, title, priority, baseline, guidance_data, params_data: [])
    ctrl = family.catalog_controls.find_or_initialize_by(control_id: control_id)
    is_new = ctrl.new_record?
    attrs = {
      title:            title.presence || ctrl.title,
      priority:         priority.presence || ctrl.priority,
      baseline_impact:  baseline.presence || ctrl.baseline_impact,
      guidance_data:    guidance_data.any? ? guidance_data : (ctrl.guidance_data || {})
    }
    attrs[:params_data] = params_data if params_data.present?
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
  #   "a."  → "a"    (letter — appended directly: "AC-01" + "a" = "AC-01a")
  #   "1."  → ".1"   (digit  — dot separator:     "AC-01a" + ".1" = "AC-01a.1")
  #   "(a)" → ".(a)" (paren  — dot separator:     "AC-01a.1" + ".(a)" = "AC-01a.1.(a)")
  def label_to_suffix(label)
    l = label.strip
    case l
    when /\A([a-z])\.\z/    then $1          # "a." → "a"
    when /\A(\d+)\.\z/      then ".#{$1}"    # "1." → ".1"
    when /\A\([^)]+\)\z/    then ".#{l}"     # "(a)" → ".(a)"
    else ".#{l.chomp('.')}"                  # fallback
    end
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
end
