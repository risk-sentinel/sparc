require "rails_helper"

RSpec.describe PoamYamlParserService do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/poam/ifa_plan-of-action-and-milestones.yaml") }
  let(:document) { create(:poam_document, file_type: "yaml", status: "processing") }
  let(:service) { described_class.new(document, fixture_path.to_s) }

  describe "#parse" do
    it "parses the YAML file and creates POAM items" do
      service.parse
      document.reload

      expect(document.poam_items.count).to be > 0
    end

    it "sets OSCAL version from metadata" do
      service.parse
      document.reload

      expect(document.oscal_version).to be_present
    end

    it "creates observations from the fixture" do
      service.parse
      document.reload

      expect(document.poam_observations.count).to be > 0
    end

    it "creates risks from the fixture" do
      service.parse
      document.reload

      expect(document.poam_risks.count).to be > 0
    end

    it "reads valid YAML without errors" do
      expect { service.parse }.not_to raise_error
    end
  end
end
