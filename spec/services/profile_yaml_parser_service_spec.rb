require "rails_helper"

RSpec.describe ProfileYamlParserService do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/profiles/basic-profile.yaml") }
  let(:document) { create(:profile_document, file_type: "yaml", status: "processing") }
  let(:service) { described_class.new(document, fixture_path.to_s) }

  describe "#parse" do
    it "parses the YAML file and creates profile controls" do
      service.parse
      document.reload

      expect(document.profile_controls.count).to be > 0
    end

    it "sets OSCAL version from metadata" do
      service.parse
      document.reload

      expect(document.oscal_version).to be_present
    end

    it "creates controls with control_ids" do
      service.parse
      document.reload

      control_ids = document.profile_controls.pluck(:control_id).compact
      expect(control_ids).not_to be_empty
    end

    it "reads valid YAML without errors" do
      expect { service.parse }.not_to raise_error
    end
  end
end
