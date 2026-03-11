require "rails_helper"

RSpec.describe SspYamlParserService do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/ssp/ifa_ssp-example.yaml") }
  let(:document) { create(:ssp_document, file_type: "yaml", status: "processing") }
  let(:service) { described_class.new(document, fixture_path.to_s) }

  describe "#parse" do
    it "parses the YAML file and creates controls" do
      service.parse
      document.reload

      expect(document.ssp_controls.count).to be > 0
    end

    it "creates controls with control_ids" do
      service.parse
      document.reload

      control_ids = document.ssp_controls.pluck(:control_id).compact
      expect(control_ids).not_to be_empty
    end

    it "sets OSCAL version from metadata" do
      service.parse
      document.reload

      expect(document.oscal_version).to be_present
      expect(document.oscal_version).to eq("1.1.2")
    end

    it "sets document metadata" do
      service.parse
      document.reload

      expect(document.oscal_version).to be_present
    end

    it "reads valid YAML without errors" do
      expect { service.parse }.not_to raise_error
    end
  end
end
