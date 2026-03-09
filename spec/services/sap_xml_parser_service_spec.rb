require "rails_helper"

RSpec.describe SapXmlParserService do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/sap/ifa_assessment-plan-example.xml") }
  let(:document) { create(:sap_document, file_type: "xml", status: "processing") }
  let(:service) { described_class.new(document, fixture_path.to_s) }

  describe "#parse" do
    it "parses the XML file and creates controls" do
      service.parse
      document.reload

      expect(document.status).to eq("completed")
      expect(document.sap_controls.count).to be > 0
    end

    it "sets OSCAL version from XML metadata" do
      service.parse
      document.reload

      expect(document.oscal_version).to be_present
      expect(document.oscal_version).to eq("1.1.2")
    end

    it "sets metadata from XML" do
      service.parse
      document.reload

      expect(document.oscal_version).to be_present
    end

    it "reads valid XML without errors" do
      expect { service.parse }.not_to raise_error
    end
  end
end
