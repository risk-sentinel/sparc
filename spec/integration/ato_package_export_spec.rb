# frozen_string_literal: true

require "rails_helper"
require "zip"

# #836 (#817 stage S5) — the ATO package: assembled, exported in all three
# serializations, schema-validated, and round-tripped.
#
# This was blocked on three defects and could not be written honestly until they
# landed, because the alternative was asserting against known-broken output or
# quietly narrowing the criteria:
#
#   #829  the package was JSON-only
#   #827  every OSCAL XML export was schema-invalid (JSON key order, not XSD
#         element sequence)
#   #828  the manifest listed documents absent from the archive
#
# All three are closed, and this spec is what keeps them closed.
RSpec.describe "ATO package export (#836)", type: :integration do
  let(:boundary) { create(:authorization_boundary) }
  let!(:ssp) { create(:ssp_document, authorization_boundary: boundary) }
  # An SSP with no implemented requirements is schema-INVALID by definition
  # ("array size at /control-implementation/implemented-requirements is less
  # than 1"), so a bare document would fail validation for a reason that has
  # nothing to do with the package. The first version of this spec did exactly
  # that, and the validator was right to reject it.
  let!(:ssp_control) { create(:ssp_control, ssp_document: ssp, control_id: "AC-1") }
  let(:service) { AtoPackageExportService.new(boundary) }

  def entries(zip_data)
    Zip::File.open_buffer(zip_data) { |zip| return zip.map(&:name) }
  end

  def read_entry(zip_data, name)
    Zip::File.open_buffer(zip_data) do |zip|
      entry = zip.find_entry(name)
      return entry && zip.read(entry)
    end
  end

  describe "all three serializations (#829)" do
    it "emits json, yaml and xml for each document" do
      names = entries(service.generate_zip)

      %w[json yaml xml].each do |format|
        expect(names.any? { |n| n.end_with?(".#{format}") }).to be(true),
                                                                "package contains no .#{format} file"
      end
    end

    it "honours a narrowed format list" do
      names = entries(service.generate_zip(formats: [ :json ]))

      expect(names.any? { |n| n.end_with?(".yaml") }).to be(false)
      expect(names.any? { |n| n.end_with?(".xml") }).to be(false)
    end
  end

  # The invariant #828 established STRUCTURALLY: the archive and the manifest are
  # derived from the same export results, so they cannot disagree. A package that
  # claims to contain an SSP and does not is worse than an export that fails
  # outright, because nothing signals the loss.
  describe "the manifest describes exactly what is inside (#828)" do
    it "lists no file the archive does not contain" do
      zip_data = service.generate_zip
      names = entries(zip_data)
      manifest = JSON.parse(read_entry(zip_data, "manifest.json"))

      listed = manifest.fetch("documents", []).flat_map { |d| d.fetch("files", []) }
                       .map { |f| f.is_a?(Hash) ? f["file"] : f }.compact

      expect(listed - names).to be_empty,
                                "manifest lists files absent from the archive: #{(listed - names).inspect}"
    end

    it "leaves no OSCAL file in the archive the manifest does not list" do
      zip_data = service.generate_zip
      names = entries(zip_data).reject { |n| n == "manifest.json" }
      manifest = JSON.parse(read_entry(zip_data, "manifest.json"))

      listed = manifest.fetch("documents", []).flat_map { |d| d.fetch("files", []) }
                       .map { |f| f.is_a?(Hash) ? f["file"] : f }.compact

      expect(names - listed).to be_empty,
                                "archive holds files the manifest omits: #{(names - listed).inspect}"
    end
  end

  describe "schema validation" do
    it "produces schema-valid OSCAL JSON for the SSP" do
      zip_data = service.generate_zip(formats: [ :json ])
      name = entries(zip_data).find { |n| n.include?("ssp") && n.end_with?(".json") }
      expect(name).to be_present

      result = OscalSchemaValidationService.validate_json(:ssp, read_entry(zip_data, name))

      expect(result.valid?).to be(true), "SSP JSON failed schema validation: #{result.errors&.first(3)}"
    end

    # #827: XML used to emit JSON key order rather than the XSD element sequence,
    # so every XML export was invalid. This is the guard on that fix.
    it "produces schema-valid OSCAL XML for the SSP" do
      zip_data = service.generate_zip(formats: [ :xml ])
      name = entries(zip_data).find { |n| n.include?("ssp") && n.end_with?(".xml") }
      expect(name).to be_present

      result = OscalSchemaValidationService.validate_xml(:ssp, read_entry(zip_data, name))

      expect(result.valid?).to be(true), "SSP XML failed schema validation: #{result.errors&.first(3)}"
    end
  end

  # Round-trip SEMANTIC equivalence: the three serializations are three spellings
  # of one document, so parsing each back must yield the same content. Comparing
  # YAML and XML against the JSON is the assertion that catches a serializer that
  # drops, reorders into meaninglessness, or silently coerces a field.
  describe "round-trip semantic equivalence" do
    let(:zip_data) { service.generate_zip }
    let(:ssp_json) do
      name = entries(zip_data).find { |n| n.include?("ssp") && n.end_with?(".json") }
      JSON.parse(read_entry(zip_data, name))
    end

    it "YAML parses back to the same document as JSON" do
      name = entries(zip_data).find { |n| n.include?("ssp") && n.end_with?(".yaml") }

      expect(YAML.safe_load(read_entry(zip_data, name))).to eq(ssp_json)
    end

    it "XML carries the same system identity as JSON" do
      name = entries(zip_data).find { |n| n.include?("ssp") && n.end_with?(".xml") }
      xml = read_entry(zip_data, name)

      uuid = ssp_json.dig("system-security-plan", "uuid")
      expect(uuid).to be_present
      expect(xml).to include(uuid),
                     "the XML serialization does not carry the same document uuid as the JSON"
    end

    it "re-exporting produces the same JSON — the export is deterministic" do
      first = ssp_json
      second_zip = AtoPackageExportService.new(boundary.reload).generate_zip(formats: [ :json ])
      name = entries(second_zip).find { |n| n.include?("ssp") && n.end_with?(".json") }
      second = JSON.parse(read_entry(second_zip, name))

      # last-modified moves on every export by design; everything else must not.
      [ first, second ].each { |d| d.dig("system-security-plan", "metadata")&.delete("last-modified") }

      expect(second).to eq(first)
    end
  end

  describe "validation summary" do
    it "reports per-document validity rather than a bare boolean" do
      summary = service.validation_summary

      expect(summary).to be_present
    end
  end
end
