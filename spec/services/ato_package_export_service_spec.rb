# frozen_string_literal: true

require "rails_helper"

RSpec.describe AtoPackageExportService do
  let(:ab) { create(:authorization_boundary) }

  describe "#generate_zip" do
    context "when SSP is linked" do
      let(:ssp) { create(:ssp_document, :enriched, authorization_boundary: ab) }

      before { ssp } # ensure SSP is created

      it "includes ssp.json in the ZIP" do
        allow_any_instance_of(OscalSspExportService)
          .to receive(:export_unvalidated)
          .and_return('{"system-security-plan": {}}')

        zip_data = described_class.new(ab).generate_zip
        entries = extract_zip_entries(zip_data)

        expect(entries).to include("ssp.json")
      end
    end

    context "when SAP is linked" do
      let(:sap) { create(:sap_document, authorization_boundary: ab) }

      before { sap }

      it "includes sap.json in the ZIP" do
        allow_any_instance_of(OscalAssessmentPlanExportService)
          .to receive(:export_unvalidated)
          .and_return('{"assessment-plan": {}}')

        zip_data = described_class.new(ab).generate_zip
        entries = extract_zip_entries(zip_data)

        expect(entries).to include("sap.json")
      end
    end

    context "when SAR is linked" do
      let(:sar) { create(:sar_document, authorization_boundary: ab) }

      before { sar }

      it "includes sar.json in the ZIP" do
        allow_any_instance_of(OscalSarExportService)
          .to receive(:export_unvalidated)
          .and_return('{"assessment-results": {}}')

        zip_data = described_class.new(ab).generate_zip
        entries = extract_zip_entries(zip_data)

        expect(entries).to include("sar.json")
      end
    end

    context "when POAM documents are linked" do
      let!(:poam) { create(:poam_document, authorization_boundary: ab) }

      it "includes poam-1.json in the ZIP" do
        allow_any_instance_of(OscalPoamExportService)
          .to receive(:export_unvalidated)
          .and_return('{"plan-of-action-and-milestones": {}}')

        zip_data = described_class.new(ab).generate_zip
        entries = extract_zip_entries(zip_data)

        expect(entries).to include("poam-1.json")
      end
    end

    it "always includes manifest.json" do
      zip_data = described_class.new(ab).generate_zip
      entries = extract_zip_entries(zip_data)

      expect(entries).to include("manifest.json")
    end

    it "manifest contains authorization boundary info" do
      zip_data = described_class.new(ab).generate_zip
      manifest = extract_zip_file(zip_data, "manifest.json")
      parsed = JSON.parse(manifest)

      expect(parsed["authorization_boundary"]["name"]).to eq(ab.name)
      expect(parsed["authorization_boundary"]["status"]).to eq(ab.status)
      expect(parsed).to have_key("documents")
      expect(parsed).to have_key("validation")
    end

    context "when no documents are linked" do
      it "returns a ZIP with only manifest.json" do
        zip_data = described_class.new(ab).generate_zip
        entries = extract_zip_entries(zip_data)

        expect(entries).to eq([ "manifest.json" ])
      end
    end

    context "when CDEF documents are linked through boundaries" do
      let(:boundary) { create(:boundary, authorization_boundary: ab) }
      let(:cdef) { create(:cdef_document, name: "Test CDEF") }

      before do
        create(:boundary_cdef_document, boundary: boundary, cdef_document: cdef)
      end

      it "includes cdef JSON file in the ZIP" do
        allow_any_instance_of(OscalComponentDefinitionExportService)
          .to receive(:export_unvalidated)
          .and_return('{"component-definition": {}}')

        zip_data = described_class.new(ab).generate_zip
        entries = extract_zip_entries(zip_data)

        expect(entries.any? { |e| e.start_with?("cdef-") }).to be true
      end
    end
  end

  describe "#validation_summary" do
    context "when documents are linked" do
      let(:ssp) { create(:ssp_document, :enriched, authorization_boundary: ab) }

      before { ssp }

      it "returns validation status for linked documents" do
        valid_result = instance_double("ValidationResult", valid?: true, errors: [])
        allow_any_instance_of(OscalSspExportService)
          .to receive(:validation_result)
          .and_return(valid_result)

        summary = described_class.new(ab).validation_summary

        expect(summary[:ssp][:name]).to eq(ssp.name)
        expect(summary[:ssp][:valid]).to be true
        expect(summary[:ssp][:errors]).to be_empty
      end

      it "includes errors when validation fails" do
        invalid_result = instance_double("ValidationResult",
          valid?: false,
          errors: [ "missing required field", "invalid UUID" ])
        allow_any_instance_of(OscalSspExportService)
          .to receive(:validation_result)
          .and_return(invalid_result)

        summary = described_class.new(ab).validation_summary

        expect(summary[:ssp][:valid]).to be false
        expect(summary[:ssp][:errors]).to include("missing required field")
      end
    end

    context "when documents are not linked" do
      it "returns 'Not linked' error for missing SSP" do
        summary = described_class.new(ab).validation_summary

        expect(summary[:ssp][:name]).to be_nil
        expect(summary[:ssp][:valid]).to be_nil
        expect(summary[:ssp][:errors]).to include("Not linked")
      end

      it "returns 'Not linked' error for missing SAP" do
        summary = described_class.new(ab).validation_summary

        expect(summary[:sap][:valid]).to be_nil
        expect(summary[:sap][:errors]).to include("Not linked")
      end

      it "returns 'Not linked' error for missing SAR" do
        summary = described_class.new(ab).validation_summary

        expect(summary[:sar][:valid]).to be_nil
        expect(summary[:sar][:errors]).to include("Not linked")
      end
    end

    context "when validation raises an exception" do
      let(:ssp) { create(:ssp_document, :enriched, authorization_boundary: ab) }

      before { ssp }

      it "catches the error and returns it in the summary" do
        allow_any_instance_of(OscalSspExportService)
          .to receive(:validation_result)
          .and_raise(StandardError, "schema file not found")

        summary = described_class.new(ab).validation_summary

        expect(summary[:ssp][:valid]).to be false
        expect(summary[:ssp][:errors]).to include("schema file not found")
      end
    end
  end

  private

  def extract_zip_entries(zip_data)
    entries = []
    io = StringIO.new(zip_data)
    Zip::InputStream.open(io) do |zip|
      while (entry = zip.get_next_entry)
        entries << entry.name
      end
    end
    entries
  end

  def extract_zip_file(zip_data, filename)
    io = StringIO.new(zip_data)
    Zip::InputStream.open(io) do |zip|
      while (entry = zip.get_next_entry)
        return zip.read if entry.name == filename
      end
    end
    nil
  end
end
