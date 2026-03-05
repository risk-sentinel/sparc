class ProfileXccdfParserService
  include BatchInsertable

  def initialize(profile_document, file_path)
    @document  = profile_document
    @file_path = file_path
  end

  def parse
    xml_content = File.read(@file_path).force_encoding("UTF-8")
    doc = Nokogiri::XML(xml_content) { |c| c.strict.noblanks }
    doc.remove_namespaces!

    benchmark = doc.at_xpath("//Benchmark")
    raise "No <Benchmark> element found in XCCDF file" unless benchmark

    profile_type = detect_profile_type(benchmark)
    update_document_metadata(benchmark, profile_type)

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

    batch_insert_records(
      control_class: ProfileControl,
      field_class:   ProfileControlField,
      document_fk:   :profile_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  private

  def detect_profile_type(benchmark)
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

  def update_document_metadata(benchmark, profile_type)
    @document.update!(
      profile_type:    profile_type,
      profile_version: benchmark.at_xpath("version")&.text&.strip,
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

    control_family = derive_control_family(cci_refs, rule_id)

    attrs = {
      control_id:     rule_id,
      title:          title,
      severity:       severity,
      control_family: control_family,
      cci_references: cci_refs.join(","),
      row_order:      row_order,
      group_id:       group_id,
      rule_id:        rule_id
    }

    fields = {}
    fields["description"]   = description   if description.present?
    fields["fix_text"]      = fix_text       if fix_text.present?
    fields["check_content"] = check_content  if check_content.present?
    fields["check_system"]  = check_system   if check_system.present?
    fields["severity"]      = severity       if severity.present?
    fields["cci_refs"]      = cci_refs.join(", ") if cci_refs.any?
    fields["rationale"]     = rationale      if rationale.present?

    [ attrs, fields ]
  end

  def extract_description(rule)
    desc_node = rule.at_xpath("description")
    return nil unless desc_node
    raw = desc_node.text.to_s.strip

    if raw.include?("<VulnDiscussion>")
      begin
        inner = Nokogiri::XML("<root>#{raw}</root>").at_xpath("//VulnDiscussion")
        return inner&.text&.strip if inner
      rescue Nokogiri::XML::SyntaxError
        # Fall through to raw text
      end
    end

    raw.presence
  end

  def derive_control_family(_cci_refs, rule_id)
    # Attempt to derive from rule_id prefix
    if rule_id.to_s.match?(/\A[A-Z]{2}-/)
      rule_id.split("-").first.upcase
    else
      nil
    end
  end
end
