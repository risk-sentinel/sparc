# frozen_string_literal: true

# Parses a DISA STIG XCCDF XML file and creates/extends a stig_to_nist
# Converter with ConverterEntry records mapping SV/V-IDs → NIST controls.
#
# Each STIG upload extends the same cumulative converter — duplicate
# source→target pairs from prior uploads are skipped.
#
# The CCI→NIST resolution uses the same cci_to_nist.json data as
# FrameworkMappingGeneratorService, ensuring consistency.
#
# Usage:
#   service = StigConverterService.new(xml_content, "U_RHEL_9_STIG_V2R7.xml")
#   result  = service.call
#   # => { converter:, benchmark_title:, new_entries:, skipped:, total_rules: }
#
class StigConverterService
  class ParseError < StandardError; end

  # STIG vulnerability id (e.g. "V-12345") extracted from XCCDF ids.
  V_ID_PATTERN = /(V-\d+)/i

  CONVERTER_NAME = "DISA STIG SV/V to NIST SP 800-53"

  def initialize(xml_content, original_filename = "stig.xml")
    @xml_content      = xml_content
    @original_filename = original_filename
    @cci_lookup       = nil
  end

  def call
    doc = parse_xml
    benchmark = doc.at_xpath("//Benchmark")
    raise ParseError, "No <Benchmark> element found in XCCDF file" unless benchmark

    benchmark_title = benchmark.at_xpath("title")&.text&.strip || "Unknown STIG"
    benchmark_id    = benchmark["id"].to_s
    version         = benchmark.at_xpath("version")&.text&.strip

    converter = find_or_create_converter

    # Extract rules and resolve CCI→NIST mappings
    rules = extract_rules(benchmark)
    raise ParseError, "No STIG rules with V/SV IDs found. Verify this is a valid XCCDF STIG file." if rules.empty?

    # Build entries, skipping duplicates
    existing_pairs = load_existing_pairs(converter)
    new_entries = []
    skipped = 0

    rules.each do |rule|
      nist_targets = resolve_nist_controls(rule[:ccis])
      source_id = rule[:sv_id].presence || rule[:v_id]

      if nist_targets.any?
        nist_targets.each do |nist_id, cci|
          pair_key = "#{source_id}|#{nist_id}"
          if existing_pairs.include?(pair_key)
            skipped += 1
            next
          end
          existing_pairs.add(pair_key)

          new_entries << {
            uuid: SecureRandom.uuid,
            converter_id: converter.id,
            source_id: source_id,
            target_id: nist_id,
            relationship: "subset",
            category: rule[:severity] || "medium",
            remarks: "via #{cci}; STIG: #{benchmark_title}",
            row_order: new_entries.size
          }
        end
      else
        # No CCI→NIST resolution — record the rule with target "unmapped"
        pair_key = "#{source_id}|unmapped"
        unless existing_pairs.include?(pair_key)
          existing_pairs.add(pair_key)
          new_entries << {
            uuid: SecureRandom.uuid,
            converter_id: converter.id,
            source_id: source_id,
            target_id: "unmapped",
            relationship: "intersects",
            category: rule[:severity] || "medium",
            remarks: "No CCI mapping found; STIG: #{benchmark_title}",
            row_order: new_entries.size
          }
        end
      end
    end

    # Batch insert new entries
    if new_entries.any?
      ConverterEntry.insert_all(new_entries)
    end

    # Update converter metadata
    update_converter_metadata(converter, benchmark_title, benchmark_id, version)

    {
      converter: converter.reload,
      benchmark_title: benchmark_title,
      new_entries: new_entries.size,
      skipped: skipped,
      total_rules: rules.size
    }
  end

  private

  def parse_xml
    doc = XmlSecurity.parse(@xml_content)
    doc.remove_namespaces!
    doc
  rescue Nokogiri::XML::SyntaxError => e
    raise ParseError, "Invalid XML: #{e.message.truncate(200)}"
  end

  def find_or_create_converter
    converter = Converter.find_by(converter_type: "stig_to_nist")

    unless converter
      converter = Converter.create!(
        name: CONVERTER_NAME,
        description: "Cumulative DISA STIG SV/V-ID to NIST SP 800-53 control mappings " \
                     "extracted from XCCDF benchmark files via CCI resolution.",
        converter_type: "stig_to_nist",
        version: "1.0",
        status: "draft",
        source_framework: "DISA STIG XCCDF",
        target_framework: "NIST SP 800-53"
      )
    end

    converter
  end

  def extract_rules(benchmark)
    rules = []

    benchmark.xpath(".//Group").each do |group|
      group.xpath("Rule").each do |rule|
        rule_id  = rule["id"].to_s
        severity = rule["severity"].to_s

        # V-ID from <version> element or Group id
        version_el = rule.at_xpath("version")
        v_id = version_el&.text&.strip || ""
        v_match = v_id.match(V_ID_PATTERN) || group["id"].to_s.match(V_ID_PATTERN) || rule_id.match(V_ID_PATTERN)
        v_id = v_match ? v_match[1] : ""

        # SV-ID from rule id attribute
        sv_match = rule_id.match(/(SV-\d+r?\d*)/i)
        sv_id = sv_match ? sv_match[1] : ""

        next if sv_id.blank? && v_id.blank?

        # CCI references
        ccis = rule.xpath("ident[@system='http://cyber.mil/cci']")
                   .map(&:text).map(&:strip).reject(&:blank?)

        # Fallback for non-standard CCI references
        if ccis.empty?
          ccis = rule.xpath("ident").map(&:text).map(&:strip)
                     .select { |r| r.match?(/\ACCI-\d+\z/i) }
        end

        title = rule.at_xpath("title")&.text&.strip || ""

        rules << {
          rule_id: rule_id,
          sv_id: sv_id,
          v_id: v_id,
          severity: severity.presence || "medium",
          ccis: ccis,
          title: title
        }
      end
    end

    rules
  end

  def resolve_nist_controls(ccis)
    results = []

    ccis.each do |cci|
      nist_id = cci_lookup[cci.upcase]
      results << [ nist_id, cci ] if nist_id.present?
    end

    results.uniq { |nist_id, _| nist_id }
  end

  def cci_lookup
    @cci_lookup ||= load_cci_lookup
  end

  def load_cci_lookup
    path = Rails.root.join("lib", "data_mappings", "cci_to_nist.json")
    raise ParseError, "CCI mapping file not found at #{path}" unless File.exist?(path)

    data = JSON.parse(File.read(path))
    lookup = {}

    Array(data["mappings"]).each do |entry|
      cci = entry["cci"].to_s.upcase
      nist = entry["nist_rev5"].presence || entry["nist_rev4"].presence
      lookup[cci] = nist if nist.present?
    end

    lookup
  end

  def load_existing_pairs(converter)
    converter.converter_entries
             .pluck(:source_id, :target_id)
             .map { |s, t| "#{s}|#{t}" }
             .to_set
  end

  def update_converter_metadata(converter, benchmark_title, benchmark_id, version)
    imported_stigs = Array(converter.metadata_extra["imported_stigs"])
    imported_stigs << {
      "benchmark_title" => benchmark_title,
      "benchmark_id" => benchmark_id,
      "version" => version,
      "filename" => @original_filename,
      "imported_at" => Time.current.iso8601
    }

    converter.update!(
      status: "complete",
      metadata_extra: converter.metadata_extra.merge(
        "imported_stigs" => imported_stigs,
        "last_import" => Time.current.iso8601
      )
    )
  end
end
