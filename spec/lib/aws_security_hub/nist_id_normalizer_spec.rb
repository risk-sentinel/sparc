# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_security_hub/nist_id_normalizer")

RSpec.describe AwsSecurityHub::NistIdNormalizer do
  describe ".normalize" do
    it "returns lowercase bare control for plain family-number" do
      expect(described_class.normalize("AC-3")).to eq([ "ac-3" ])
    end

    it "handles multi-digit control numbers" do
      expect(described_class.normalize("SI-12")).to eq([ "si-12" ])
    end

    it "renders numeric paren as a dotted enhancement" do
      expect(described_class.normalize("AC-2(1)")).to eq([ "ac-2.1" ])
    end

    it "renders single-letter paren as a subpart with _smt suffix" do
      expect(described_class.normalize("AC-2(j)")).to eq([ "ac-2_smt.j" ])
    end

    it "expands composite enhancement + subparts into multiple ids" do
      result = described_class.normalize("IA-5(1)(a)(d)(e)")
      expect(result).to eq([ "ia-5.1_smt.a", "ia-5.1_smt.d", "ia-5.1_smt.e" ])
    end

    it "returns empty array for nil input" do
      expect(described_class.normalize(nil)).to eq([])
    end

    it "returns empty array for blank input" do
      expect(described_class.normalize("")).to eq([])
      expect(described_class.normalize("   ")).to eq([])
    end

    it "returns empty array for malformed input (no dash)" do
      expect(described_class.normalize("AC2")).to eq([])
    end

    it "returns empty for non-NIST prefix lengths" do
      # NIST 800-53 control families are always 2 letters (AC, AU, CM, ...).
      # 3-letter prefixes are rejected; the converter seeder additionally
      # filters against the actual catalog so unknown 2-letter families
      # also fall out downstream.
      expect(described_class.normalize("FOO-1")).to eq([])
      expect(described_class.normalize("A-1")).to eq([])
    end

    it "skips multi-letter paren tokens silently" do
      # MITRE data is well-formed but a hypothetical bad token shouldn't blow
      # up the whole row -- the bare stem still passes through.
      expect(described_class.normalize("AC-2(xy)")).to eq([ "ac-2" ])
    end
  end

  describe ".normalize_all" do
    it "flattens and deduplicates across an array of MITRE ids" do
      input = [ "AC-3", "AC-2(1)", "AC-3", "AC-2(j)" ]
      expect(described_class.normalize_all(input)).to eq([ "ac-3", "ac-2.1", "ac-2_smt.j" ])
    end

    it "returns empty array for nil input" do
      expect(described_class.normalize_all(nil)).to eq([])
    end

    it "expands composite ids while deduplicating" do
      input = [ "IA-5(1)(a)", "IA-5(1)(a)(d)" ]
      expect(described_class.normalize_all(input)).to eq([ "ia-5.1_smt.a", "ia-5.1_smt.d" ])
    end
  end

  describe ".to_oscal_lowercase" do
    it "lowercases bare strings" do
      expect(described_class.to_oscal_lowercase("AC-2")).to eq("ac-2")
    end

    it "handles already-lowercase input idempotently" do
      expect(described_class.to_oscal_lowercase("ac-2.1")).to eq("ac-2.1")
    end
  end
end
