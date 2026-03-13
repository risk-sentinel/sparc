# frozen_string_literal: true

namespace :mapping do
  desc "Generate cci_to_nist.json from DISA CCI XML (download U_CCI_List.xml to tmp/ first)"
  task import_cci: :environment do
    xml_path = Rails.root.join("tmp", "U_CCI_List.xml")
    unless File.exist?(xml_path)
      abort <<~MSG
        CCI XML not found at #{xml_path}

        Download from: https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_CCI_List.zip
        Unzip and place U_CCI_List.xml in the tmp/ directory, then re-run this task.
      MSG
    end

    puts "Parsing #{xml_path}..."
    doc = Nokogiri::XML(File.read(xml_path))
    doc.remove_namespaces!

    mappings = doc.xpath("//cci_item").filter_map do |item|
      cci_id = item["id"]
      refs = item.xpath("references/reference")

      nist_rev5 = refs.find { |r| r["version"].to_s.include?("5") }&.[]("index")
      nist_rev4 = refs.find { |r| r["version"].to_s.include?("4") }&.[]("index")

      next unless nist_rev5 || nist_rev4

      {
        "cci"       => cci_id,
        "nist_rev5" => normalize_nist_id(nist_rev5),
        "nist_rev4" => normalize_nist_id(nist_rev4),
        "status"    => item.at_xpath("status")&.text || "published"
      }
    end

    output = {
      "format"        => "cci_mapping",
      "version"       => Time.current.strftime("%Y.%m"),
      "source"        => "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_CCI_List.zip",
      "description"   => "DISA CCI to NIST SP 800-53 mapping (Rev 4 + Rev 5)",
      "total_entries" => mappings.size,
      "mappings"      => mappings
    }

    out_path = Rails.root.join("lib", "data_mappings", "cci_to_nist.json")
    File.write(out_path, JSON.pretty_generate(output))
    puts "Wrote #{mappings.size} CCI mappings to #{out_path}"
  end
end

def normalize_nist_id(raw)
  return nil if raw.blank?
  raw.strip.downcase
     .gsub(/\s*\(\s*/, ".")   # "AC-2 (1)" → "ac-2.1"
     .gsub(")", "")
     .gsub(/\s+/, "-")
end
