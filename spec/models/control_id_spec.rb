# frozen_string_literal: true

require "rails_helper"

# #852 — one canonical control identifier, replacing a dozen ad-hoc transformers.
#
# The highest-risk part of this change is that `canonical` feeds OSCAL fields
# typed **TokenDatatype** (`control-id`, `target-id` in ssp, profile,
# component-definition, assessment-plan, assessment-results and poam). Those
# exports validate today, so the consolidation is only safe if the new
# implementation reproduces the old one exactly. That equivalence is asserted
# first, before anything else.
RSpec.describe ControlId do
  # The exact body of the four byte-identical private normalizers being
  # replaced (sar_from_ssp_service, oscal_ssp_export_service,
  # oscal_sar_export_service, sar_wizard_service), reproduced verbatim so the
  # comparison is against what actually shipped rather than a description of it.
  def legacy_normalize(raw_id)
    return "unknown" if raw_id.blank?

    raw_id.strip
          .downcase
          .gsub(/\s+/, "-")
          .gsub("(", ".")
          .gsub(")", "")
          .gsub(/\.{2,}/, ".")
          .gsub(/-\./, ".")
  end

  # Inputs drawn from what actually appears in this codebase: catalog imports,
  # spreadsheet uploads, the demo seed (padded), OSCAL files (canonical), and
  # NIST publication text (parenthesised).
  UNPADDED_INPUTS = [
    "AC-2", "ac-2", "AC-2 (1)", "ac-2.1", "AC-2(1)", " AC-2 ", "AC-2  (1)",
    "SC-7", "si-4.12", "AU-6 (3)", "CM-6", "RA-5", "IA-5 (1)", "PM-6",
    "ac-2.1.2", "AC-2 (1) (2)", "unknown-1"
  ].freeze

  describe "equivalence with the normalizer it replaces (the safety gate)" do
    UNPADDED_INPUTS.each do |input|
      it "produces the legacy result for #{input.inspect}" do
        expect(described_class.canonical(input)).to eq(legacy_normalize(input))
      end
    end

    it "matches on blank input, which the legacy version mapped to 'unknown'" do
      [ nil, "", "   " ].each do |blank|
        expect(described_class.canonical(blank)).to eq(legacy_normalize(blank))
        expect(described_class.canonical(blank)).to eq("unknown")
      end
    end

    # The ONE intended divergence. The legacy version left zero-padding intact,
    # so "AC-02" stayed "ac-02" and never matched "ac-2" — the defect this
    # issue exists to close. Called out explicitly so the divergence is a
    # decision on the record rather than an accident.
    it "DIVERGES from legacy only by removing zero padding" do
      expect(legacy_normalize("AC-02")).to eq("ac-02")
      expect(described_class.canonical("AC-02")).to eq("ac-2")
    end
  end

  describe "OSCAL token conformance" do
    # control-id / target-id are TokenDatatype:  ^(\p{L}|_)(\p{L}|\p{N}|[.\-_])*$
    (UNPADDED_INPUTS + [ "AC-02", "AC-02 (01)", "ac-02.01" ]).each do |input|
      it "emits a legal OSCAL token for #{input.inspect}" do
        result = described_class.canonical(input)

        expect(described_class).to be_token(result), "#{input.inspect} -> #{result.inspect}"
        expect(result).not_to include("(")
        expect(result).not_to include(")")
        expect(result).not_to include(" ")
      end
    end
  end

  describe ".canonical" do
    it "converts an enhancement to dot notation" do
      expect(described_class.canonical("AC-2 (1)")).to eq("ac-2.1")
    end

    it "removes zero padding from base and enhancement alike" do
      expect(described_class.canonical("AC-02")).to eq("ac-2")
      expect(described_class.canonical("AC-02 (01)")).to eq("ac-2.1")
      expect(described_class.canonical("ac-02.01")).to eq("ac-2.1")
    end

    it "keeps a single zero rather than deleting the digit" do
      expect(described_class.canonical("AC-0")).to eq("ac-0")
    end

    it "is idempotent" do
      UNPADDED_INPUTS.each do |input|
        once = described_class.canonical(input)
        expect(described_class.canonical(once)).to eq(once), input
      end
    end
  end

  describe ".same? — the comparison that was missing" do
    it "treats padded and unpadded as the same control" do
      expect(described_class).to be_same("AC-02", "ac-2")
      expect(described_class).to be_same("AC-2", "ac-02")
    end

    it "treats parenthesised and dotted enhancements as the same control" do
      expect(described_class).to be_same("AC-2 (1)", "ac-2.1")
      expect(described_class).to be_same("AC-02 (01)", "AC-2(1)")
    end

    it "still distinguishes genuinely different controls" do
      expect(described_class).not_to be_same("AC-2", "AC-3")
      expect(described_class).not_to be_same("AC-2", "AC-2.1")
      expect(described_class).not_to be_same("AC-2", "AU-2")
    end

    it "is false for blanks rather than matching everything" do
      expect(described_class).not_to be_same(nil, "AC-2")
      expect(described_class).not_to be_same("AC-2", "")
      expect(described_class).not_to be_same(nil, nil)
    end
  end

  describe ".padded and .human" do
    it "renders the SPARC display form" do
      expect(described_class.padded("ac-2")).to eq("AC-02")
      expect(described_class.padded("AC-2 (1)")).to eq("AC-02.01")
    end

    it "renders the NIST publication form" do
      expect(described_class.human("ac-2")).to eq("AC-2")
      expect(described_class.human("ac-2.1")).to eq("AC-2 (1)")
      expect(described_class.human("AC-02 (01)")).to eq("AC-2 (1)")
    end

    it "round-trips every form back to one canonical value" do
      %w[AC-2 ac-2 AC-02 ac-2.1 AC-02.01].each do |input|
        canonical = described_class.canonical(input)
        expect(described_class.canonical(described_class.padded(input))).to eq(canonical)
        expect(described_class.canonical(described_class.human(input))).to eq(canonical)
      end
    end
  end

  describe ".include? and .canonical_set" do
    it "matches a selection against stored ids regardless of padding" do
      stored = %w[AC-02 AU-06 SC-07]

      expect(described_class).to be_include(stored, "ac-2")
      expect(described_class).to be_include(stored, "AC-2 (0)".sub(" (0)", ""))
      expect(described_class).not_to be_include(stored, "AC-3")
    end

    it "builds a set that compares canonically" do
      set = described_class.canonical_set([ "AC-02", "ac-2", nil, "" ])

      expect(set).to eq(Set["ac-2"])
    end
  end
end
