class CdefXccdfParserService
  include BatchInsertable
  include ProgressTrackable
  include CciNistResolvable

  def initialize(cdef_document, file_path)
    @document  = cdef_document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    xml_content = File.read(@file_path).force_encoding("UTF-8")
    doc = XmlSecurity.parse(xml_content)
    doc.remove_namespaces!

    # Auto-detect OSCAL component-definition vs XCCDF Benchmark
    if doc.at_xpath("//component-definition")
      parse_oscal_xml(doc)
    elsif doc.at_xpath("//Benchmark")
      parse_xccdf(doc)
    else
      raise "Unrecognized XML format: expected <Benchmark> (XCCDF) or <component-definition> (OSCAL)"
    end
  end

  private

  # ── OSCAL Component Definition XML ─────────────────────────────

  def parse_oscal_xml(doc)
    json_hash = build_oscal_json_from_xml(doc)

    temp_path = Rails.root.join("tmp", "cdef_oscal_#{SecureRandom.hex(8)}.json").to_s
    File.write(temp_path, JSON.generate(json_hash))

    begin
      CdefJsonParserService.new(@document, temp_path).parse
    ensure
      FileUtils.rm_f(temp_path)
    end
  end

  def build_oscal_json_from_xml(doc)
    cdef_node = doc.at_xpath("//component-definition")
    metadata_node = cdef_node.at_xpath("metadata")

    metadata = {}
    metadata["title"]         = metadata_node.at_xpath("title")&.text&.strip
    metadata["last-modified"] = metadata_node.at_xpath("last-modified")&.text&.strip
    metadata["version"]       = metadata_node.at_xpath("version")&.text&.strip
    metadata["oscal-version"] = metadata_node.at_xpath("oscal-version")&.text&.strip

    metadata["roles"] = metadata_node.xpath("role").map do |role|
      { "id" => role["id"], "title" => role.at_xpath("title")&.text&.strip }.compact
    end
    metadata["roles"] = nil if metadata["roles"].empty?

    metadata["parties"] = metadata_node.xpath("party").map do |party|
      build_party_hash(party)
    end
    metadata["parties"] = nil if metadata["parties"].empty?

    components = cdef_node.xpath("component").map { |c| build_component_hash(c) }

    back_matter = build_back_matter(cdef_node.at_xpath("back-matter"))

    {
      "component-definition" => {
        "uuid"     => cdef_node["uuid"],
        "metadata" => metadata.compact,
        "components" => components
      }.tap { |h| h["back-matter"] = back_matter if back_matter }
    }
  end

  def build_party_hash(party)
    h = { "uuid" => party["uuid"], "type" => party["type"], "name" => party.at_xpath("name")&.text&.strip }
    links = party.xpath("link").map { |l| { "href" => l["href"], "rel" => l["rel"] }.compact }
    h["links"] = links unless links.empty?
    h.compact
  end

  def build_component_hash(component)
    h = {
      "uuid"        => component["uuid"],
      "type"        => component["type"],
      "title"       => component.at_xpath("title")&.text&.strip,
      "description" => extract_prose(component.at_xpath("description"))
    }

    cis = component.xpath("control-implementation").map { |ci| build_control_implementation_hash(ci) }
    h["control-implementations"] = cis unless cis.empty?
    h.compact
  end

  def build_control_implementation_hash(ci)
    h = {
      "uuid"        => ci["uuid"],
      "source"      => ci["source"],
      "description" => extract_prose(ci.at_xpath("description"))
    }

    reqs = ci.xpath("implemented-requirement").map { |ir| build_implemented_requirement_hash(ir) }
    h["implemented-requirements"] = reqs unless reqs.empty?
    h.compact
  end

  def build_implemented_requirement_hash(ir)
    h = {
      "uuid"        => ir["uuid"],
      "control-id"  => ir["control-id"],
      "description" => extract_prose(ir.at_xpath("description"))
    }

    params = ir.xpath("set-parameter").map do |sp|
      { "param-id" => sp["param-id"], "values" => sp.xpath("value").map { |v| v.text.strip } }.compact
    end
    h["set-parameters"] = params unless params.empty?

    statements = ir.xpath("statement").map do |stmt|
      s = {
        "statement-id" => stmt["statement-id"],
        "uuid"         => stmt["uuid"],
        "description"  => extract_prose(stmt.at_xpath("description"))
      }
      s.compact
    end
    h["statements"] = statements unless statements.empty?

    h.compact
  end

  def extract_prose(node)
    return nil unless node
    # Collect text content from all child <p> elements, or use direct text
    paragraphs = node.xpath("p")
    if paragraphs.any?
      paragraphs.map { |p| p.text.strip }.join("\n")
    else
      node.text.strip.presence
    end
  end

  def build_back_matter(bm_node)
    return nil unless bm_node

    resources = bm_node.xpath("resource").map do |res|
      r = { "uuid" => res["uuid"] }
      desc = extract_prose(res.at_xpath("description"))
      r["description"] = desc if desc
      rlinks = res.xpath("rlink").map { |rl| { "href" => rl["href"], "media-type" => rl["media-type"] }.compact }
      r["rlinks"] = rlinks unless rlinks.empty?
      r.compact
    end

    { "resources" => resources } unless resources.empty?
  end

  # ── XCCDF Benchmark ────────────────────────────────────────────

  def parse_xccdf(doc)
    benchmark = doc.at_xpath("//Benchmark")

    cdef_type = detect_cdef_type(benchmark)
    update_document_metadata(benchmark, cdef_type)

    control_attrs = []
    field_entries = []
    row_order     = 0

    benchmark.xpath(".//Group").each do |group|
      group.xpath("Rule").each do |rule|
        attrs, fields = parse_rule(group, rule, row_order)
        idx = control_attrs.size
        control_attrs << attrs
        fields.each { |fname, fval| field_entries << [ idx, fname, fval ] }
        row_order += 1
      end
    end

    update_processing_stage!(:creating_records)
    batch_insert_records(
      control_class: CdefControl,
      field_class:   CdefControlField,
      document_fk:   :cdef_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  def detect_cdef_type(benchmark)
    bench_id    = benchmark["id"].to_s
    title       = benchmark.at_xpath("title")&.text.to_s
    source      = benchmark.at_xpath("//source")&.text.to_s

    if bench_id.match?(/stig/i) || title.match?(/stig/i) || source.match?(/stig\.dod\.mil/i)
      "disa_stig"
    elsif bench_id.match?(/cis/i) || title.match?(/\bcis\b/i)
      "cis"
    else
      "scap"
    end
  end

  def update_document_metadata(benchmark, cdef_type)
    @document.update!(
      cdef_type:       cdef_type,
      cdef_version:    benchmark.at_xpath("version")&.text&.strip,
      benchmark_id:    benchmark["id"],
      description:     benchmark.at_xpath("description")&.text&.strip&.truncate(5000),
      import_metadata: {
        "title"        => benchmark.at_xpath("title")&.text&.strip,
        "status"       => benchmark.at_xpath("status")&.text&.strip,
        "release_info" => benchmark.at_xpath("plain-text[@id='release-info']")&.text&.strip
      }.compact
    )
  end

  def parse_rule(group, rule, row_order)
    rule_id       = rule["id"]
    severity      = rule["severity"]
    group_id      = group["id"]
    title         = rule.at_xpath("title")&.text&.strip
    description   = extract_description(rule)
    fix_text      = rule.at_xpath("fixtext")&.text&.strip
    check_content = rule.at_xpath("check/check-content")&.text&.strip
    check_system  = rule.at_xpath("check")&.[]("system")
    rationale     = rule.at_xpath("rationale")&.text&.strip

    cci_refs = rule.xpath("ident[@system='http://cyber.mil/cci']")
                   .map(&:text).map(&:strip).reject(&:blank?)

    # Also try generic ident elements for non-DISA formats
    if cci_refs.empty?
      cci_refs = rule.xpath("ident").map(&:text).map(&:strip)
                     .select { |r| r.start_with?("CCI-") }
    end

    # Resolve SV/V-ID → NIST control ID via Converter + CCI fallback
    sv_id = extract_sv_id(rule_id)
    nist_id = resolve_nist_for_stig(sv_id, cci_refs) if sv_id.present?
    control_family = nist_id.present? ? nist_family_from_id(nist_id) : nil

    attrs = {
      control_id:     nist_id || rule_id,
      title:          title,
      severity:       severity,
      control_family: control_family,
      cci_references: cci_refs.join(","),
      row_order:      row_order,
      group_id:       group_id,
      rule_id:        rule_id,
      stig_id:        rule_id
    }

    fields = {}
    fields["description"]   = description   if description.present?
    fields["fix_text"]      = fix_text       if fix_text.present?
    fields["check_content"] = check_content  if check_content.present?
    fields["check_system"]  = check_system   if check_system.present?
    fields["severity"]      = severity       if severity.present?
    fields["cci_refs"]      = cci_refs.join(", ") if cci_refs.any?
    fields["rationale"]     = rationale      if rationale.present?
    fields["nist_controls"] = nist_id        if nist_id.present?

    [ attrs, fields ]
  end

  def extract_description(rule)
    desc_node = rule.at_xpath("description")
    return nil unless desc_node
    raw = desc_node.text.to_s.strip

    if raw.include?("<VulnDiscussion>")
      begin
        inner = XmlSecurity.parse("<root>#{raw}</root>").at_xpath("//VulnDiscussion")
        return inner&.text&.strip if inner
      rescue Nokogiri::XML::SyntaxError
        # Fall through to raw text
      end
    end

    raw.presence
  end

  # derive_control_family is now handled via CciNistResolvable#nist_family_from_id
end
