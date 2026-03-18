# frozen_string_literal: true

require "rails_helper"

RSpec.describe SspXmlParserService do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/ssp/oscal_leveraging-example_ssp.xml") }
  let(:document) { create(:ssp_document, name: "XML Parser Test SSP", status: "processing") }

  describe "#parse" do
    it "parses OSCAL XML and creates controls" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.creation_method).to eq("oscal_import")
      expect(document.ssp_controls.count).to be > 0
    end

    it "creates components from system-implementation" do
      described_class.new(document, fixture_path.to_s).parse

      expect(document.ssp_components.count).to be > 0
    end

    it "extracts metadata via JSON parser delegation" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.oscal_version).to be_present
    end

    it "raises on invalid root element" do
      bad_xml = "<not-an-ssp><title>Bad</title></not-an-ssp>"
      file = Tempfile.new([ "bad_ssp", ".xml" ])
      file.write(bad_xml)
      file.rewind

      expect {
        described_class.new(document, file.path).parse
      }.to raise_error(RuntimeError, /missing <system-security-plan>/)
    ensure
      file.close
      file.unlink
    end
  end
end
