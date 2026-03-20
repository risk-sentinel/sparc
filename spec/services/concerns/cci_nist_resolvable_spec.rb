# frozen_string_literal: true

require "rails_helper"

# Test harness: a simple class that includes the concern
class CciNistResolvableTestHarness
  include CciNistResolvable

  # Expose private methods for testing
  public :resolve_nist_for_stig, :normalize_nist_tag, :nist_family_from_id, :extract_sv_id
end

RSpec.describe CciNistResolvable do
  let(:harness) { CciNistResolvableTestHarness.new }

  describe "#normalize_nist_tag" do
    it 'converts "CM-6 b" to "cm-6.b"' do
      expect(harness.normalize_nist_tag("CM-6 b")).to eq("cm-6.b")
    end

    it 'converts "AC-2 (1)" to "ac-2.1"' do
      expect(harness.normalize_nist_tag("AC-2 (1)")).to eq("ac-2.1")
    end

    it 'converts "SI-2" to "si-2"' do
      expect(harness.normalize_nist_tag("SI-2")).to eq("si-2")
    end

    it 'converts "AC-8 a" to "ac-8.a"' do
      expect(harness.normalize_nist_tag("AC-8 a")).to eq("ac-8.a")
    end

    it 'converts "AC-8 c 1" to "ac-8.c.1"' do
      # "AC-8 c 1" has sub-parts "c" and "1" separated by spaces
      expect(harness.normalize_nist_tag("AC-8 c 1")).to eq("ac-8.c.1")
    end

    it "returns nil for blank input" do
      expect(harness.normalize_nist_tag("")).to be_nil
      expect(harness.normalize_nist_tag(nil)).to be_nil
    end

    it "handles already-lowercase input" do
      expect(harness.normalize_nist_tag("cm-6")).to eq("cm-6")
    end
  end

  describe "#nist_family_from_id" do
    it 'extracts "CM" from "cm-6.b"' do
      expect(harness.nist_family_from_id("cm-6.b")).to eq("CM")
    end

    it 'extracts "AC" from "ac-2.1"' do
      expect(harness.nist_family_from_id("ac-2.1")).to eq("AC")
    end

    it "returns nil for blank input" do
      expect(harness.nist_family_from_id("")).to be_nil
      expect(harness.nist_family_from_id(nil)).to be_nil
    end
  end

  describe "#extract_sv_id" do
    it 'strips revision suffix: "SV-257777r925318_rule" → "SV-257777"' do
      expect(harness.extract_sv_id("SV-257777r925318_rule")).to eq("SV-257777")
    end

    it "handles bare SV-ID" do
      expect(harness.extract_sv_id("SV-257777")).to eq("SV-257777")
    end

    it "returns nil for non-SV identifiers" do
      expect(harness.extract_sv_id("V-257777")).to be_nil
      expect(harness.extract_sv_id("RHEL-09-211010")).to be_nil
    end
  end

  describe "#resolve_nist_for_stig" do
    context "with Converter entries" do
      before do
        converter = Converter.create!(
          name: "Test STIG Converter",
          converter_type: "stig_to_nist",
          version: "1.0",
          status: "complete",
          source_framework: "DISA STIG XCCDF",
          target_framework: "NIST SP 800-53"
        )
        ConverterEntry.create!(
          converter: converter,
          source_id: "SV-257777",
          target_id: "cm-6",
          relationship: "subset"
        )
      end

      it "resolves via Converter first" do
        expect(harness.resolve_nist_for_stig("SV-257777", [ "CCI-000366" ])).to eq("cm-6")
      end
    end

    context "with CCI fallback (no Converter)" do
      it "resolves CCI-000366 to a NIST control" do
        result = harness.resolve_nist_for_stig("SV-999999", [ "CCI-000366" ])
        expect(result).to be_present
        expect(result).to match(/\A[a-z]{2}-\d+/)
      end
    end

    context "with no matching data" do
      it "returns nil" do
        result = harness.resolve_nist_for_stig("SV-000001", [ "CCI-999999" ])
        expect(result).to be_nil
      end
    end

    context "with unmapped Converter entry" do
      before do
        converter = Converter.create!(
          name: "Test STIG Converter",
          converter_type: "stig_to_nist",
          version: "1.0",
          status: "complete",
          source_framework: "DISA STIG XCCDF",
          target_framework: "NIST SP 800-53"
        )
        ConverterEntry.create!(
          converter: converter,
          source_id: "SV-111111",
          target_id: "unmapped",
          relationship: "intersects"
        )
      end

      it "falls through to CCI lookup when Converter entry is unmapped" do
        # unmapped entry should be skipped, falls to CCI
        result = harness.resolve_nist_for_stig("SV-111111", [ "CCI-000366" ])
        expect(result).to be_present
      end
    end
  end
end
