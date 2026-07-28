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

  # ── #828 — the manifest must describe what the archive actually contains ──
  #
  # It used to be built from the boundary's ASSOCIATIONS while the archive was
  # built from exports that could fail. A failed export was skipped silently and
  # the manifest went on naming the missing file, with the only trace a server
  # log line the customer never sees.
  describe "when a document export fails (#828)" do
    let!(:ssp) { create(:ssp_document, :enriched, authorization_boundary: ab) }

    before do
      allow_any_instance_of(OscalSspExportService)
        .to receive(:export_unvalidated).and_raise(StandardError, "boom")
    end

    it "does not list a file it did not write" do
      zip_data = described_class.new(ab).generate_zip
      entries = extract_zip_entries(zip_data)
      manifest = JSON.parse(extract_zip_file(zip_data, "manifest.json"))

      listed = manifest["documents"].flat_map { |d| d["files"].map { |f| f["file"] } }

      expect(listed - entries).to be_empty,
        "manifest names #{(listed - entries).inspect}, which is not in the archive"
    end

    it "tells the caller the document was omitted, and why" do
      zip_data = described_class.new(ab).generate_zip
      manifest = JSON.parse(extract_zip_file(zip_data, "manifest.json"))

      omitted = manifest["omitted"]
      expect(omitted.map { |o| o["type"] }).to include("ssp"),
        "a dropped document must be stated in the artifact the customer receives, not only in a server log"
      expect(omitted.first["error"]).to include("boom")
      expect(manifest["documents"].map { |d| d["type"] }).not_to include("ssp")
    end
  end

  # ── #829 — the package is the artifact an assessor receives ──────────────
  describe "serializations (#829)" do
    let!(:ssp) { create(:ssp_document, :enriched, authorization_boundary: ab) }

    it "emits JSON, YAML and XML for each document" do
      entries = extract_zip_entries(described_class.new(ab).generate_zip)

      expect(entries).to include("ssp.json", "ssp.yaml", "ssp.xml")
    end

    it "records the serialization and conformance of every file in the manifest" do
      zip_data = described_class.new(ab).generate_zip
      manifest = JSON.parse(extract_zip_file(zip_data, "manifest.json"))
      files = manifest["documents"].find { |d| d["type"] == "ssp" }["files"]

      expect(files.map { |f| f["format"] }).to contain_exactly("json", "yaml", "xml")
      expect(files.map { |f| f.key?("schema_valid") }).to all(be(true))
    end

    # The archive ships unvalidated bytes on purpose, so a partial package stays
    # recoverable. #828 requires that to be stated rather than implied.
    it "says outright that its contents are unvalidated" do
      zip_data = described_class.new(ab).generate_zip
      manifest = JSON.parse(extract_zip_file(zip_data, "manifest.json"))

      expect(manifest.dig("export", "contents")).to eq("unvalidated")
      expect(manifest.dig("export", "note")).to include("schema_valid")
    end

    it "can emit a single serialization on request" do
      entries = extract_zip_entries(described_class.new(ab).generate_zip(formats: [ :json ]))

      expect(entries).to include("ssp.json")
      expect(entries).not_to include("ssp.yaml", "ssp.xml")
    end

    # The XML half of #829 depended on #827: before it, EVERY OSCAL XML export
    # was schema-invalid because the converter emitted JSON key order instead of
    # the XSD sequence. That is what this pins — not that any given document is
    # complete, but that the XML serialization is no worse than the JSON one.
    #
    # Asserting the two AGREE is the discriminating check. A document with
    # missing content is invalid in both, which says nothing about the
    # converter; the #827 signature is precisely JSON valid while XML is not.
    it "does not make XML any less conformant than JSON (#827)" do
      zip_data = described_class.new(ab).generate_zip
      manifest = JSON.parse(extract_zip_file(zip_data, "manifest.json"))

      manifest["documents"].each do |doc|
        by_format = doc["files"].to_h { |f| [ f["format"], f["schema_valid"] ] }

        expect(by_format["xml"]).to eq(by_format["json"]),
          "#{doc['type']}: JSON schema_valid=#{by_format['json']} but XML=#{by_format['xml']}. " \
          "XML conforming differently from JSON is the #827 signature (element order), " \
          "not a content problem — a document missing content fails BOTH."
      end
    end

    # Guards the check above from being vacuous: `schema_valid` must reflect
    # the real state, not be hard-coded or defaulted.
    it "reports schema_valid honestly for a document with missing content" do
      zip_data = described_class.new(ab).generate_zip
      manifest = JSON.parse(extract_zip_file(zip_data, "manifest.json"))
      ssp_entry = manifest["documents"].find { |d| d["type"] == "ssp" }

      # This factory SSP carries no implemented-requirements, which OSCAL
      # requires — so every serialization of it must report as non-conforming.
      expect(ssp_entry["files"].map { |f| f["schema_valid"] }).to all(be(false)),
        "an incomplete document was reported as schema-valid — the flag is not measuring anything"
    end
  end

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
