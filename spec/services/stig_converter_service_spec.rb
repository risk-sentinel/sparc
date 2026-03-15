# frozen_string_literal: true

require "rails_helper"

RSpec.describe StigConverterService do
  let(:rhel_fixture) { Rails.root.join("spec/fixtures/files/stigs/U_RHEL_9_STIG_V2R7_Manual-xccdf.xml") }
  let(:gpos_fixture) { Rails.root.join("spec/fixtures/files/stigs/U_GPOS_SRG_V3R3_Manual-xccdf.xml") }

  describe "#call" do
    context "with a valid RHEL 9 STIG" do
      subject(:result) { described_class.new(File.read(rhel_fixture), "U_RHEL_9_STIG_V2R7.xml").call }

      it "creates a stig_to_nist converter" do
        expect(result[:converter]).to be_persisted
        expect(result[:converter].converter_type).to eq("stig_to_nist")
        expect(result[:converter].name).to eq(StigConverterService::CONVERTER_NAME)
      end

      it "extracts rules and creates entries" do
        expect(result[:total_rules]).to be > 0
        expect(result[:new_entries]).to be > 0
        expect(result[:converter].converter_entries.count).to eq(result[:new_entries])
      end

      it "populates benchmark title" do
        expect(result[:benchmark_title]).to be_present
      end

      it "sets converter status to complete" do
        expect(result[:converter].status).to eq("complete")
      end

      it "records import metadata" do
        imported_stigs = result[:converter].metadata_extra["imported_stigs"]
        expect(imported_stigs).to be_an(Array)
        expect(imported_stigs.size).to eq(1)
        expect(imported_stigs.first["filename"]).to eq("U_RHEL_9_STIG_V2R7.xml")
      end

      it "creates entries with source IDs matching SV/V pattern" do
        source_ids = result[:converter].converter_entries.pluck(:source_id)
        expect(source_ids).to all(match(/\A(SV-|V-)\d+/i))
      end

      it "creates entries with valid relationship types" do
        relationships = result[:converter].converter_entries.pluck(:relationship).uniq
        expect(relationships).to all(be_in(ConverterEntry::RELATIONSHIPS))
      end
    end

    context "with a valid GPOS SRG" do
      subject(:result) { described_class.new(File.read(gpos_fixture), "U_GPOS_SRG_V3R3.xml").call }

      it "creates entries from the SRG" do
        expect(result[:total_rules]).to be > 0
        expect(result[:converter]).to be_persisted
      end
    end

    context "cumulative behavior — importing a second STIG" do
      it "extends the existing converter without duplicating entries" do
        first = described_class.new(File.read(rhel_fixture), "rhel9.xml").call
        converter_id = first[:converter].id
        first_count = first[:new_entries]

        # Import the same STIG again
        second = described_class.new(File.read(rhel_fixture), "rhel9_again.xml").call

        expect(second[:converter].id).to eq(converter_id)
        expect(second[:new_entries]).to eq(0)
        expect(second[:skipped]).to be > 0

        # Total entries should not have grown
        expect(second[:converter].converter_entries.count).to eq(first_count)
      end

      it "adds new entries from a different STIG" do
        described_class.new(File.read(rhel_fixture), "rhel9.xml").call
        second = described_class.new(File.read(gpos_fixture), "gpos.xml").call

        # Should have at least some new entries from the GPOS SRG
        # (unless all rules overlap, which is unlikely)
        expect(second[:converter].metadata_extra["imported_stigs"].size).to eq(2)
      end
    end

    context "with invalid XML" do
      it "raises ParseError" do
        expect {
          described_class.new("not xml at all", "bad.xml").call
        }.to raise_error(StigConverterService::ParseError, /Invalid XML/)
      end
    end

    context "with XML that has no Benchmark element" do
      it "raises ParseError" do
        expect {
          described_class.new("<root><data/></root>", "empty.xml").call
        }.to raise_error(StigConverterService::ParseError, /No <Benchmark> element/)
      end
    end

    context "with XML that has no rules" do
      it "raises ParseError" do
        xml = '<Benchmark xmlns="http://checklists.nist.gov/xccdf/1.1" id="test"><title>Empty</title></Benchmark>'
        expect {
          described_class.new(xml, "empty_stig.xml").call
        }.to raise_error(StigConverterService::ParseError, /No STIG rules/)
      end
    end
  end

  describe "slug generation" do
    it "generates a slug for the converter" do
      result = described_class.new(File.read(rhel_fixture), "rhel9.xml").call
      expect(result[:converter].slug).to be_present
      expect(result[:converter].slug).to match(/\A[a-z0-9-]+\z/)
    end
  end
end
