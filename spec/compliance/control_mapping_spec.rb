# frozen_string_literal: true

require "rails_helper"

# docs/compliance/nist-sp800-53-rev5-mapping.md is the artifact an assessor reads
# first, and its Summary Statistics are the first thing they read in it.
#
# ── Why this exists (#1117) ────────────────────────────────────────────────
#
# Those tables were hand-maintained and had drifted badly: they claimed 247
# controls against 313 actual rows, 11 of the 20 per-family counts were wrong,
# and the By Family column did not even sum to the total the same section
# printed twice (280 vs 247). Two rows also carried a Responsibility and a
# Status outside the vocabularies the document defines at the top, which put
# them outside every tally — so the numbers were not merely stale, they could
# not be reproduced from the rows by anyone checking.
#
# Nothing detected any of that, because a markdown table has no consumer that
# would object. This is that consumer.
#
# The counting rule, stated once: only rows in the per-family sections
# (`## AC -- ...` through `## SR -- ...`) count. The themed sections after them
# revisit controls already listed — 32 rows — and counting those again would
# double-count them.
RSpec.describe "NIST 800-53 control mapping" do
  # `let`, not constants: a constant assigned inside a describe block lands on
  # Object and is visible to every other spec in the suite.
  let(:mapping_path)   { Rails.root.join("docs/compliance/nist-sp800-53-rev5-mapping.md") }
  let(:family_heading) { /\A## ([A-Z]{2}) -- / }
  let(:control_row)    { /\A\|\s*[A-Z]{2}-\d+(?:\(\d+\))?\s*\|/ }

  # A control row, as the family tables write it:
  #   | ID | Title | Baseline | Responsibility | Implementation Summary | ... | Status |
  let(:responsibility_column) { 3 }
  let(:status_column)         { -1 }

  let(:source) { mapping_path.read }
  let(:lines)  { source.lines.map(&:chomp) }

  # Rows grouped by the family heading they appear under. Any other `## `
  # heading closes the family, which is what excludes the themed sections.
  let(:rows_by_family) do
    family = nil
    lines.each_with_object(Hash.new { |h, k| h[k] = [] }) do |line, acc|
      if (match = line.match(family_heading))
        family = match[1]
        acc[family] # touch, so a family with no rows still appears
        next
      end
      family = nil if line.start_with?("## ")
      next if family.nil? || !line.match?(control_row)

      acc[family] << line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
    end
  end

  let(:rows)  { rows_by_family.values.flatten(1) }
  let(:total) { rows.size }

  # Parse a `| key | count | ... |` table that follows the given `###` heading,
  # stopping at the next heading. Returns { key => count }, Total included.
  def summary_table(heading)
    body = source.split(/^#{Regexp.escape(heading)}$/).last.split(/^#/).first.to_s
    body.lines.filter_map do |line|
      cells = line.strip.delete_prefix("|").delete_suffix("|").split("|").map { |c| c.strip.delete("*") }
      next if cells.size < 2 || cells[1].blank? || !cells[1].match?(/\A\d+\z/)

      [ cells[0], cells[1].to_i ]
    end.to_h
  end

  # The vocabularies the document defines for itself, read from the "How to Use
  # This Document" tables rather than copied here — so widening a vocabulary is
  # a documentation edit, and using a value that was never defined is a failure.
  def declared_vocabulary(label)
    body = source.split(/^\*\*#{Regexp.escape(label)}:\*\*$/).last.split(/^\*\*/).first.to_s
    body.lines.filter_map do |line|
      cells = line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
      next if cells.size < 2 || cells[0].in?([ "Label", "Status", "---" ]) || cells[0].start_with?("---")

      cells[0]
    end
  end

  it "has control rows to count" do
    expect(total).to be > 250,
      "if the family tables moved or were renamed, this spec silently counts nothing"
  end

  describe "the vocabularies the document defines" do
    it "covers every Responsibility a control row uses" do
      used    = rows.map { |cells| cells[responsibility_column] }.uniq
      undeclared = used - declared_vocabulary("Responsibility values")

      expect(undeclared).to be_empty,
        -> { "Responsibility values used by rows but never defined: #{undeclared.inspect}. " \
             "A value outside the vocabulary falls out of every tally." }
    end

    it "covers every Status a control row uses" do
      used       = rows.map { |cells| cells[status_column] }.uniq
      undeclared = used - declared_vocabulary("Status values")

      expect(undeclared).to be_empty,
        -> { "Status values used by rows but never defined: #{undeclared.inspect}. " \
             "A value outside the vocabulary falls out of every tally." }
    end
  end

  describe "Summary Statistics" do
    it "reports the number of controls the family tables actually list" do
      [ "### By Responsibility", "### By Status", "### By Family" ].each do |heading|
        expect(summary_table(heading)["Total"]).to eq(total),
          -> { "#{heading} claims #{summary_table(heading)['Total']} controls; the family tables list #{total}." }
      end
    end

    it "matches the By Responsibility tally" do
      expected = rows.map { |cells| cells[responsibility_column] }.tally
      expect(summary_table("### By Responsibility").except("Total")).to eq(expected)
    end

    it "matches the By Status tally" do
      expected = rows.map { |cells| cells[status_column] }.tally
      expect(summary_table("### By Status").except("Total")).to eq(expected)
    end

    it "matches the per-family counts" do
      expected = rows_by_family.transform_values(&:size)
      expect(summary_table("### By Family").except("Total")).to eq(expected)
    end

    # The failure that made the old section self-contradictory: its own By
    # Family column summed to 280 while the Total cell below it said 247.
    it "sums its own By Family column to the total it prints" do
      table = summary_table("### By Family")
      expect(table.except("Total").values.sum).to eq(table["Total"])
    end
  end
end
