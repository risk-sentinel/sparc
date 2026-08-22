# frozen_string_literal: true

require "rails_helper"

# #1030 — `ControlId.control_key` reduces a NIST reference to the control a
# catalog actually holds.
#
# The CCI mapping data is statement-level. NIST catalogs contain controls and
# enhancements and never statement parts, so storing a statement reference in
# `control_id` — a column used to join against the catalog — matched nothing:
# 57% of CCI resolutions produced an id present in no catalog.
RSpec.describe ControlId, ".control_key" do
  {
    # unchanged — already catalog-addressable
    "ac-2"        => "ac-2",
    "ac-2.1"      => "ac-2.1",
    "si-2"        => "si-2",
    # statement parts, dropped
    "cm-6-b"      => "cm-6",
    "ac-2.a"      => "ac-2",
    "pm-14-a-1"   => "pm-14",
    "ac-1-a-1.a"  => "ac-1",
    "cp-2-a-4"    => "cp-2",
    # enhancement kept, statement dropped
    "ia-5.1.a"    => "ia-5.1",
    "cm-5.5.b"    => "cm-5.5",
    "ac-20.1.a"   => "ac-20.1",
    "si-4.4.b"    => "si-4.4",
    # the other legitimate spellings reduce too, via canonical
    "AC-02"       => "ac-2",
    "CM-6 b"      => "cm-6",
    "AC-2 (1)"    => "ac-2.1"
  }.each do |input, expected|
    it "reduces #{input.inspect} to #{expected.inspect}" do
      expect(described_class.control_key(input)).to eq(expected)
    end
  end

  it "is idempotent — reducing a reduced key changes nothing" do
    %w[ac-2 ac-2.1 cm-6 ia-5.1].each do |key|
      expect(described_class.control_key(key)).to eq(key)
    end
  end

  # `canonical` is schema-validated in every OSCAL document SPARC exports, so
  # this must be a separate reduction rather than a change to it.
  it "does not alter what canonical produces" do
    expect(described_class.canonical("AC-2 (1)")).to eq("ac-2.1")
    expect(described_class.canonical("cm-6-b")).to eq("cm-6-b")
  end

  describe "the mapping data it was measured against" do
    let(:mappings) do
      JSON.parse(Rails.root.join("lib/data_mappings/cci_to_nist.json").read)["mappings"]
    end
    let(:references) do
      mappings.filter_map { |e| e["nist_rev5"].presence || e["nist_rev4"].presence }
    end

    # The reduction rule assumes a hyphen suffix is ALWAYS a statement letter.
    # If a mapping ever wrote an enhancement as `ac-2-1`, this rule would
    # silently reduce it to `ac-2` and lose the enhancement. Measured as zero
    # today; asserted so it stays a decision rather than an assumption.
    it "contains no reference whose hyphen suffix is a number" do
      numeric_suffix = references.grep(/\A\p{L}{1,3}-\d+-\d+/)

      expect(numeric_suffix).to be_empty,
        "these would lose an enhancement when reduced: #{numeric_suffix.uniq.first(10).inspect}"
    end

    it "reduces to something every reference can be looked up by" do
      expect(references).to all(match(/\A\p{L}{1,3}-\d+/)),
        "a reference that does not start family-number cannot be reduced meaningfully"
    end
  end
end
