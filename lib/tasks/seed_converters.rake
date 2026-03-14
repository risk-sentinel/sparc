# frozen_string_literal: true

namespace :converters do
  desc "Seed Converters from bundled JSON mapping files in lib/data_mappings/"
  task seed: :environment do
    mapping_files = {
      "cci_to_nist"       => "cci_to_nist.json",
      "cis_to_nist"       => "cis_to_nist.json",
      "scap_oval_to_nist" => "scap_oval_to_nist.json"
    }

    mapping_files.each do |type, filename|
      path = Rails.root.join("lib", "data_mappings", filename)
      unless path.exist?
        puts "  SKIP #{filename} (not found)"
        next
      end

      data = JSON.parse(path.read)
      name = converter_name_for(type, data)

      if Converter.exists?(converter_type: type, name: name)
        puts "  SKIP #{name} (already exists)"
        next
      end

      converter = Converter.create!(
        name:             name,
        description:      data["description"],
        converter_type:   type,
        version:          data["version"] || "1.0",
        status:           "complete",
        source_framework: data["source"],
        target_framework: "NIST SP 800-53"
      )

      count = import_entries(converter, data)
      puts "  OK   #{converter.name} — #{count} entries"
    end

    puts "Done."
  end
end

def converter_name_for(type, data)
  case type
  when "cci_to_nist"       then "DISA CCI → NIST SP 800-53"
  when "cis_to_nist"       then "CIS Controls v#{data['version'] || '8'} → NIST SP 800-53"
  when "scap_oval_to_nist" then "SCAP/OVAL → NIST SP 800-53"
  else data["description"]&.truncate(80) || type.titleize
  end
end

def import_entries(converter, data)
  count = 0

  case data["format"]
  when "cci_mapping"
    revisions = data["revisions"] || SparcConfig.cci_revisions
    Array(data["mappings"]).each do |entry|
      # Skip deprecated entries
      next if entry["status"].to_s.strip.downcase == "deprecated"

      # Create an entry for each configured revision that has a mapping
      revisions.each do |rev|
        target = entry["nist_rev#{rev}"]
        next if target.blank?

        converter.converter_entries.create!(
          source_id:    entry["cci"],
          target_id:    target,
          relationship: "equal",
          category:     "cci",
          remarks:      "Rev #{rev}",
          row_order:    count
        )
        count += 1
      end
    end

  when "cis_mapping"
    # Controls mappings (hash: CIS ID → array of { nist, relationship })
    Hash(data["controls_mappings"]).each do |cis_id, targets|
      Array(targets).each do |target|
        nist = target.is_a?(Hash) ? target["nist"] : target
        rel  = target.is_a?(Hash) ? normalize_rel(target["relationship"]) : "intersects"
        converter.converter_entries.create!(
          source_id:    cis_id,
          target_id:    nist,
          relationship: rel,
          category:     "controls",
          row_order:    count
        )
        count += 1
      end
    end
    # Benchmark mappings (array of { cis_id, nist_controls, relationship })
    Array(data["benchmark_mappings"]).each do |entry|
      Array(entry["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id:    entry["cis_id"],
          target_id:    nist,
          relationship: normalize_rel(entry["relationship"]),
          category:     "benchmark",
          remarks:      entry["cis_title"],
          row_order:    count
        )
        count += 1
      end
    end

  when "scap_mapping"
    # Check system mappings
    Array(data["check_system_mappings"]).each do |entry|
      Array(entry["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id:    entry["check_system"] || entry["label"],
          target_id:    nist,
          relationship: normalize_rel(entry["relationship"]),
          category:     "check_system",
          row_order:    count
        )
        count += 1
      end
    end
    # OVAL test type mappings
    Array(data["oval_test_type_mappings"]).each do |entry|
      Array(entry["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id:    entry["test_type"],
          target_id:    nist,
          relationship: normalize_rel(entry["relationship"]),
          category:     "oval_test_type",
          remarks:      entry["description"],
          row_order:    count
        )
        count += 1
      end
    end
    # OVAL family mappings
    Array(data["oval_family_mappings"]).each do |entry|
      Array(entry["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id:    entry["oval_family"],
          target_id:    nist,
          relationship: normalize_rel(entry["relationship"]),
          category:     "oval_family",
          row_order:    count
        )
        count += 1
      end
    end
    # Keyword category mappings
    Array(data["xccdf_category_mappings"]).each do |entry|
      Array(entry["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id:    entry["category"],
          target_id:    nist,
          relationship: normalize_rel(entry["relationship"]),
          category:     "keyword",
          remarks:      Array(entry["keywords"]).first(5).join(", "),
          row_order:    count
        )
        count += 1
      end
    end
  end

  count
end

def normalize_rel(rel)
  return "intersects" if rel.blank?

  cleaned = rel.to_s.gsub(/-of$/, "").gsub("-", "_").downcase
  ConverterEntry::RELATIONSHIPS.include?(cleaned) ? cleaned : "intersects"
end
