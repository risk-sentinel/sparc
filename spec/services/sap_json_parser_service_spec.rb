require "rails_helper"

RSpec.describe SapJsonParserService do
  let(:document) { create(:sap_document, file_type: "json", status: "processing") }

  def write_fixture(hash)
    path = Rails.root.join("tmp", "sap_objective_spec_#{SecureRandom.hex(4)}.json")
    File.write(path, JSON.dump(hash))
    path.to_s
  end

  describe "include-controls.statement-ids handling" do
    let(:plan) do
      {
        "assessment-plan" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test SAP", "version" => "1.0", "oscal-version" => "1.1.2" },
          "reviewed-controls" => {
            "control-selections" => [
              { "include-controls" => [ { "control-id" => "ac-1" } ] }
            ]
          },
          "local-definitions" => {
            "activities" => [
              {
                "uuid" => SecureRandom.uuid,
                "title" => "Examine AC-1",
                "props" => [ { "name" => "method", "value" => "EXAMINE" } ],
                "related-controls" => {
                  "control-selections" => [
                    {
                      "include-controls" => [
                        {
                          "control-id" => "ac-1",
                          "statement-ids" => [ "ac-1_obj.a-1", "ac-1_obj.a-2" ]
                        }
                      ]
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    end

    it "creates skeletal SapControlObjective records for each statement-id" do
      path = write_fixture(plan)
      described_class.new(document, path).parse

      ctrl = document.reload.sap_controls.find_by(control_id: "AC-1")
      expect(ctrl.sap_control_objectives.pluck(:objective_id))
        .to match_array([ "ac-1_obj.a-1", "ac-1_obj.a-2" ])
    end

    it "preserves the assessment_method on the parent control" do
      path = write_fixture(plan)
      described_class.new(document, path).parse

      ctrl = document.reload.sap_controls.find_by(control_id: "AC-1")
      expect(ctrl.assessment_method).to eq("examine")
    end
  end

  describe "fallback when no statement-ids are present" do
    let(:plan) do
      {
        "assessment-plan" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test SAP", "oscal-version" => "1.1.2" },
          "reviewed-controls" => {
            "control-selections" => [
              { "include-controls" => [ { "control-id" => "ac-1" } ] }
            ]
          }
        }
      }
    end

    it "creates the control without any objective records" do
      path = write_fixture(plan)
      described_class.new(document, path).parse

      ctrl = document.reload.sap_controls.find_by(control_id: "AC-1")
      expect(ctrl).to be_present
      expect(ctrl.sap_control_objectives).to be_empty
    end
  end
end
