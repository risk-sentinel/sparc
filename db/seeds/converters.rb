# Idempotent seed for converter mapping fixtures.
# Reads JSON mapping files from lib/data_mappings/ and creates
# Converter + ConverterEntry records via bulk insert.
#
# Run with: bin/rails db:seed

require "json"

MAPPINGS_DIR = Rails.root.join("lib/data_mappings")

def seed_converter(name:, converter_type:, source_framework:, version:, description:, source:)
  Converter.find_or_create_by!(name: name) do |c|
    c.converter_type   = converter_type
    c.source_framework = source_framework
    c.target_framework = "NIST SP 800-53"
    c.version          = version
    c.description      = description
    c.status           = "complete"
    c.metadata_extra   = { source: source }
  end
end

def normalize_relationship(rel)
  case rel.to_s.downcase.gsub("-", "").gsub("_", "")
  when "equal"     then "equal"
  when "equivalent" then "equivalent"
  when "subsetof", "subset" then "subset"
  when "supersetof", "superset" then "superset"
  else "intersects"
  end
end

# ── 1. DISA CCI → NIST SP 800-53 ──────────────────────────────────────
begin
cci_file = MAPPINGS_DIR.join("cci_to_nist.json")
if cci_file.exist?
  puts "Seeding DISA CCI → NIST converter..."
  data = JSON.parse(File.read(cci_file))

  converter = seed_converter(
    name: "DISA CCI → NIST SP 800-53",
    converter_type: "cci_to_nist",
    source_framework: data["source"],
    version: data["version"],
    description: data["description"],
    source: data["source"]
  )

  if converter.converter_entries.none?
    entries = []
    row = 0
    data["mappings"].each do |m|
      target = m["nist_rev5"] || m["nist_rev4"]
      next unless target.present?

      entries << {
        converter_id: converter.id,
        source_id: m["cci"],
        target_id: target,
        relationship: "intersects",
        category: m["status"],
        row_order: row += 1,
        uuid: SecureRandom.uuid,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    ConverterEntry.insert_all(entries) if entries.any?
    puts "  Loaded #{entries.length} CCI entries"
  else
    puts "  CCI entries already exist (#{converter.converter_entries.count}), skipping"
  end
end
rescue => e
  puts "  ERROR loading DISA CCI converter: #{e.class} — #{e.message}"
  Rails.logger.error("[Seed:Converters] DISA CCI failed: #{e.class} — #{e.message}")
end

# ── 2. CIS Controls → NIST SP 800-53 ──────────────────────────────────
begin
cis_file = MAPPINGS_DIR.join("cis_to_nist.json")
if cis_file.exist?
  puts "Seeding CIS Controls → NIST converter..."
  data = JSON.parse(File.read(cis_file))

  converter = seed_converter(
    name: "CIS Controls v#{data["version"]} → NIST SP 800-53",
    converter_type: "cis_to_nist",
    source_framework: data["source"],
    version: data["version"],
    description: data["description"],
    source: data["source"]
  )

  if converter.converter_entries.none?
    entries = []
    row = 0

    # Controls mappings (safeguard → NIST)
    (data["controls_mappings"] || {}).each do |safeguard_id, nist_mappings|
      Array(nist_mappings).each do |mapping|
        entries << {
          converter_id: converter.id,
          source_id: safeguard_id,
          target_id: mapping["nist"],
          relationship: normalize_relationship(mapping["relationship"]),
          category: "controls",
          row_order: row += 1,
          uuid: SecureRandom.uuid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    # Benchmark mappings (section → NIST)
    (data["benchmark_mappings"] || {}).each do |section_id, nist_mappings|
      Array(nist_mappings).each do |mapping|
        entries << {
          converter_id: converter.id,
          source_id: section_id,
          target_id: mapping["nist"],
          relationship: normalize_relationship(mapping["relationship"]),
          category: "benchmark",
          row_order: row += 1,
          uuid: SecureRandom.uuid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    ConverterEntry.insert_all(entries) if entries.any?
    puts "  Loaded #{entries.length} CIS entries"
  else
    puts "  CIS entries already exist (#{converter.converter_entries.count}), skipping"
  end
end
rescue => e
  puts "  ERROR loading CIS Controls converter: #{e.class} — #{e.message}"
  Rails.logger.error("[Seed:Converters] CIS Controls failed: #{e.class} — #{e.message}")
end

# ── 3. SCAP/OVAL → NIST SP 800-53 ─────────────────────────────────────
begin
scap_file = MAPPINGS_DIR.join("scap_oval_to_nist.json")
if scap_file.exist?
  puts "Seeding SCAP/OVAL → NIST converter..."
  data = JSON.parse(File.read(scap_file))

  converter = seed_converter(
    name: "SCAP/OVAL → NIST SP 800-53",
    converter_type: "scap_oval_to_nist",
    source_framework: data["source"],
    version: data["version"],
    description: data["description"],
    source: data["source"]
  )

  if converter.converter_entries.none?
    entries = []
    row = 0

    # Check system mappings
    (data["check_system_mappings"] || []).each do |mapping|
      (mapping["nist_controls"] || []).each do |nist|
        entries << {
          converter_id: converter.id,
          source_id: mapping["check_system"],
          target_id: nist,
          relationship: normalize_relationship(mapping["relationship"]),
          category: "check_system",
          remarks: mapping["label"],
          row_order: row += 1,
          uuid: SecureRandom.uuid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    # OVAL test type mappings
    (data["oval_test_type_mappings"] || []).each do |mapping|
      (mapping["nist_controls"] || []).each do |nist|
        entries << {
          converter_id: converter.id,
          source_id: mapping["test_type"],
          target_id: nist,
          relationship: normalize_relationship(mapping["relationship"]),
          category: "oval_test_type",
          remarks: mapping["description"],
          row_order: row += 1,
          uuid: SecureRandom.uuid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    # OVAL family mappings
    (data["oval_family_mappings"] || []).each do |mapping|
      (mapping["nist_controls"] || []).each do |nist|
        entries << {
          converter_id: converter.id,
          source_id: mapping["oval_family"],
          target_id: nist,
          relationship: normalize_relationship(mapping["relationship"]),
          category: "oval_family",
          remarks: mapping["description"],
          row_order: row += 1,
          uuid: SecureRandom.uuid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    # XCCDF category mappings
    (data["xccdf_category_mappings"] || []).each do |mapping|
      (mapping["nist_controls"] || []).each do |nist|
        entries << {
          converter_id: converter.id,
          source_id: mapping["category"],
          target_id: nist,
          relationship: normalize_relationship(mapping["relationship"]),
          category: "xccdf_keyword",
          remarks: mapping["description"],
          row_order: row += 1,
          uuid: SecureRandom.uuid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    # Filter out entries with nil source_id (prevents NOT NULL violation)
    valid_entries = entries.select { |e| e[:source_id].present? }
    if valid_entries.length < entries.length
      puts "  WARNING: Skipped #{entries.length - valid_entries.length} entries with nil source_id"
    end
    ConverterEntry.insert_all(valid_entries) if valid_entries.any?
    puts "  Loaded #{valid_entries.length} SCAP/OVAL entries"
  else
    puts "  SCAP/OVAL entries already exist (#{converter.converter_entries.count}), skipping"
  end
end
rescue => e
  puts "  ERROR loading SCAP/OVAL converter: #{e.class} — #{e.message}"
  Rails.logger.error("[Seed:Converters] SCAP/OVAL failed: #{e.class} — #{e.message}")
end

# ── Post-load verification ─────────────────────────────────────────────
expected = %w[cci_to_nist cis_to_nist scap_oval_to_nist]
loaded = Converter.where(converter_type: expected).pluck(:converter_type)
missing = expected - loaded
if missing.any?
  puts "  ⚠ WARNING: Missing converters: #{missing.join(', ')}"
  puts "  Re-run: bundle exec rails db:seed"
else
  puts "Converter seeding complete: #{Converter.count} converters, #{ConverterEntry.count} total entries"
end
