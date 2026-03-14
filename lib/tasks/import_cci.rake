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

    revisions = SparcConfig.cci_revisions
    puts "Parsing #{xml_path} (revisions: #{revisions.join(', ')})..."
    doc = Nokogiri::XML(File.read(xml_path))
    doc.remove_namespaces!

    items = doc.xpath("//cci_item")

    # Group by CCI ID to handle published/draft preference
    cci_groups = items.group_by { |item| item["id"] }
    skipped_deprecated = 0
    skipped_draft = 0

    mappings = cci_groups.filter_map do |cci_id, group_items|
      # Filter out deprecated items
      non_deprecated = group_items.reject do |item|
        status = item.at_xpath("status")&.text.to_s.strip.downcase
        if status == "deprecated"
          skipped_deprecated += 1
          true
        else
          false
        end
      end
      next if non_deprecated.empty?

      # Prefer published over draft
      selected = non_deprecated.find { |item| item.at_xpath("status")&.text.to_s.strip.downcase == "published" }
      unless selected
        selected = non_deprecated.first
      end
      skipped_draft += (non_deprecated.size - 1) if non_deprecated.size > 1

      refs = selected.xpath("references/reference")

      # Only extract configured revisions
      rev_mappings = {}
      revisions.each do |rev|
        ref = refs.find { |r| r["version"].to_s.include?(rev) }
        rev_mappings["nist_rev#{rev}"] = normalize_nist_id(ref["index"]) if ref
      end

      next if rev_mappings.values.all?(&:blank?)

      {
        "cci"    => cci_id,
        "status" => selected.at_xpath("status")&.text || "published"
      }.merge(rev_mappings)
    end

    rev_label = revisions.map { |r| "Rev #{r}" }.join(" + ")
    output = {
      "format"              => "cci_mapping",
      "version"             => Time.current.strftime("%Y.%m"),
      "source"              => SparcConfig.disa_cci_url,
      "description"         => "DISA CCI to NIST SP 800-53 mapping (#{rev_label})",
      "revisions"           => revisions,
      "total_entries"       => mappings.size,
      "skipped_deprecated"  => skipped_deprecated,
      "skipped_draft"       => skipped_draft,
      "mappings"            => mappings
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
