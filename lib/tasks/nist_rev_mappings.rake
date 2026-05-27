# #499 slice 1 — parse the official NIST SP 800-53 Rev4↔Rev5 comparison
# workbook into a normalized JSON file that the seed loader consumes
# (matches the existing lib/data_mappings/*.json pattern). The xlsx is
# vendored at lib/data_mappings/sp800-53r4-to-r5-comparison-workbook.xlsx
# for audit traceability — the JSON is what runs at seed time.
#
# Re-run after vendoring a new revision of the xlsx:
#   bin/rake nist_rev_mappings:generate
#
namespace :nist_rev_mappings do
  desc "Parse the NIST Rev4↔Rev5 comparison workbook into seed-loadable JSON"
  task generate: :environment do
    require "roo"
    require "json"

    src   = Rails.root.join("lib/data_mappings/sp800-53r4-to-r5-comparison-workbook.xlsx")
    dest  = Rails.root.join("lib/data_mappings/nist_sp800_53_rev5_to_rev4.json")
    raise "Missing source workbook: #{src}" unless File.exist?(src)

    xlsx = Roo::Spreadsheet.open(src.to_s)
    xlsx.sheet("Rev4 Rev5 Compared")

    entries = []
    skipped = { blank: 0, header: 0 }

    (3..xlsx.last_row).each do |r|
      rev5_id_raw      = xlsx.cell(r, 1).to_s.strip
      title            = xlsx.cell(r, 2).to_s.strip
      changed_elements = xlsx.cell(r, 8).to_s
      change_details   = xlsx.cell(r, 9).to_s

      if rev5_id_raw.empty?
        skipped[:blank] += 1
        next
      end

      # NIST IDs in OSCAL convention are lowercase, dot-separated for
      # enhancements (e.g. "AC-2(1)" → "ac-2.1"). The xlsx uses
      # "AC-2(1)" — convert to the OSCAL canonical form used in our
      # catalogs.
      rev5_id = normalize_id(rev5_id_raw)

      entry = build_entry(rev5_id, title, changed_elements, change_details)
      entries << entry if entry
    end

    output = {
      "format"        => "nist_sp800_53_rev5_to_rev4",
      "version"       => "2024.r5.upd1",
      "source"        => "https://csrc.nist.gov/files/pubs/sp/800/53/r5/upd1/final/docs/sp800-53r4-to-r5-comparison-workbook.xlsx",
      "description"   => "NIST SP 800-53 Rev 5 → Rev 4 mapping derived from the official comparison workbook",
      "total_entries" => entries.length,
      "mappings"      => entries
    }

    File.write(dest, JSON.pretty_generate(output) + "\n")

    by_rel = entries.group_by { |e| e["relationship"] }.transform_values(&:length)
    puts "Wrote #{dest} — #{entries.length} entries"
    puts "Relationship breakdown:"
    by_rel.sort_by { |_, n| -n }.each { |rel, n| puts sprintf("  %-12s  %4d", rel, n) }
    puts "Skipped: #{skipped.inspect}"
  end

  # Lowercase + replace "(N)" enhancement suffix with ".N" to match
  # OSCAL catalog control-id convention.
  def normalize_id(raw)
    raw.downcase.gsub(/\((\d+)\)/, '.\1').gsub(/\s+/, "")
  end

  def build_entry(rev5_id, title, changed_elements, change_details)
    if changed_elements.include?("New base control") || changed_elements.include?("New control enhancement")
      # Rev 5 only — no Rev 4 source. Skip from this direction's JSON.
      # (The reverse Rev4→Rev5 file, if generated separately, would
      # likewise skip Rev-4-withdrawn rows.)
      return nil
    end

    rel, rationale =
      if changed_elements.strip == "N" || changed_elements.blank?
        [ "equal", "No significant change between Rev 4 and Rev 5" ]
      elsif changed_elements.include?("Withdrawn") || change_details.include?("Incorporated into")
        [ "superset", "Rev 4 control withdrawn/incorporated into Rev 5 control" ]
      else
        [ "equivalent", changed_elements.split("\n").map(&:strip).reject(&:empty?).join("; ") ]
      end

    # For "Withdrawn" rows the Rev 4 ID equals the row's id (the row
    # documents a Rev-4-originated control); the change_details narrate
    # which Rev 5 control absorbed it. For non-withdrawn rows the Rev 4
    # ID is the same as the Rev 5 ID (the workbook is keyed by Rev 5 ID
    # for stable controls).
    rev4_id = rev5_id

    {
      "rev5_id"      => rev5_id,
      "rev4_id"      => rev4_id,
      "title"        => title,
      "relationship" => rel,
      "rationale"    => rationale.to_s.gsub(/\s+/, " ").strip
    }
  end
end
