require "rails_helper"

RSpec.describe SarJsonParserService do
  let(:document) { create(:sar_document, :oscal_import, status: "processing") }

  def write_fixture(hash)
    path = Rails.root.join("tmp", "sar_objective_spec_#{SecureRandom.hex(4)}.json")
    File.write(path, JSON.dump(hash))
    path.to_s
  end

  describe "objective-id finding linkage" do
    let(:results_hash) do
      {
        "assessment-results" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test SAR", "oscal-version" => "1.1.2" },
          "results" => [
            {
              "uuid" => SecureRandom.uuid,
              "title" => "Result 1",
              "start" => Time.current.iso8601,
              "findings" => [
                {
                  "uuid" => SecureRandom.uuid,
                  "title" => "Failed objective AC-1a-1",
                  "target" => {
                    "type" => "objective-id",
                    "target-id" => "ac-1_obj.a-1",
                    "status" => { "state" => "not-satisfied" }
                  }
                },
                {
                  "uuid" => SecureRandom.uuid,
                  "title" => "Control-level finding for AC-2",
                  "target" => {
                    "type" => "control",
                    "target-id" => "ac-2",
                    "status" => { "state" => "satisfied" }
                  }
                }
              ]
            }
          ]
        }
      }
    end

    it "creates SarControlObjective records for objective-id findings" do
      path = write_fixture(results_hash)
      described_class.new(document, path).parse

      ac1 = document.reload.sar_controls.find_by(control_id: "ac-1")
      expect(ac1.sar_control_objectives.pluck(:objective_id)).to include("ac-1_obj.a-1")
    end

    it "links the finding to its sar_control_objective via FK" do
      path = write_fixture(results_hash)
      described_class.new(document, path).parse

      finding = SarFinding.find_by(title: "Failed objective AC-1a-1")
      expect(finding.sar_control_objective).to be_present
      expect(finding.sar_control_objective.objective_id).to eq("ac-1_obj.a-1")
    end

    it "leaves control-level findings without an objective FK" do
      path = write_fixture(results_hash)
      described_class.new(document, path).parse

      finding = SarFinding.find_by(title: "Control-level finding for AC-2")
      expect(finding.sar_control_objective_id).to be_nil
    end

    it "splits ac-1_obj.a-1 into control 'ac-1' (creates SarControl)" do
      path = write_fixture(results_hash)
      described_class.new(document, path).parse

      expect(document.reload.sar_controls.find_by(control_id: "ac-1")).to be_present
    end
  end
end
