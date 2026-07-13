# frozen_string_literal: true

require "rails_helper"

RSpec.describe SspJsonParserService do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/ssp/oscal_leveraging-example_ssp.json") }
  let(:document) { create(:ssp_document, name: "Parser Test SSP", status: "processing") }

  describe "#parse" do
    it "parses OSCAL JSON file and sets status fields" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.creation_method).to eq("oscal_import")
      expect(document.oscal_version).to be_present
    end

    it "extracts import-profile href" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.import_profile_href).to be_present
    end

    it "creates controls from implemented-requirements" do
      described_class.new(document, fixture_path.to_s).parse

      expect(document.ssp_controls.count).to be > 0
    end

    it "creates components from system-implementation" do
      described_class.new(document, fixture_path.to_s).parse

      expect(document.ssp_components.count).to be > 0
    end

    it "creates users from system-implementation" do
      described_class.new(document, fixture_path.to_s).parse

      expect(document.ssp_users.count).to be > 0
    end

    it "stores metadata_extra with roles and parties" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.metadata_extra).to be_present
    end

    it "stores import_metadata with uuid" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.import_metadata["uuid"]).to be_present
    end
  end

  describe "#parse_from_hash" do
    it "raises on missing system-security-plan root key" do
      expect {
        described_class.new(document, nil).parse_from_hash({ "bad" => "data" })
      }.to raise_error(DocumentParseError, /missing 'system-security-plan'/)
    end

    it "maps OSCAL prop names to field names" do
      data = {
        "system-security-plan" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test", "oscal-version" => "1.1.2" },
          "import-profile" => { "href" => "#test" },
          "system-characteristics" => {
            "system-ids" => [ { "id" => "SYS-001" } ],
            "system-name" => "Test System",
            "description" => "Test",
            "status" => { "state" => "operational" },
            "security-impact-level" => {},
            "authorization-boundary" => { "description" => "boundary" },
            "system-information" => { "information-types" => [] }
          },
          "system-implementation" => {
            "components" => [
              {
                "uuid" => SecureRandom.uuid,
                "type" => "this-system",
                "title" => "Test System",
                "description" => "The system itself.",
                "status" => { "state" => "operational" }
              }
            ],
            "users" => []
          },
          "control-implementation" => {
            "description" => "Control implementations",
            "implemented-requirements" => [
              {
                "uuid" => SecureRandom.uuid,
                "control-id" => "ac-1",
                "props" => [
                  { "name" => "implementation-status", "value" => "implemented" },
                  { "name" => "control-origination", "value" => "system-specific" }
                ]
              }
            ]
          }
        }
      }

      described_class.new(document, nil).parse_from_hash(data)

      ctrl = document.ssp_controls.find_by(control_id: "ac-1")
      expect(ctrl).to be_present

      status_field = ctrl.ssp_control_fields.find_by(field_name: "status")
      expect(status_field.field_value).to eq("implemented")

      origination_field = ctrl.ssp_control_fields.find_by(field_name: "control_type")
      expect(origination_field.field_value).to eq("system-specific")
    end
  end
end
