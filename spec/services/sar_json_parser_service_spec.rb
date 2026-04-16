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

  describe "context-field enrichment from observations + findings" do
    let(:results_hash) do
      {
        "assessment-results" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Checkov SAR", "oscal-version" => "1.1.2" },
          "results" => [
            {
              "uuid" => SecureRandom.uuid,
              "title" => "Checkov result",
              "start" => Time.current.iso8601,
              "observations" => [
                {
                  "uuid" => "obs-1",
                  "title" => "PASS: CKV_AWS_41",
                  "description" => "CKV_AWS_41",
                  "methods" => [ "AUTOMATED" ],
                  "collected" => "2026-04-15T13:31:35Z",
                  "remarks" => "Resource: aws.default"
                }
              ],
              "findings" => [
                {
                  "uuid" => SecureRandom.uuid,
                  "title" => "CKV_AWS_41",
                  "description" => "Passed check on aws.default",
                  "target" => {
                    "type" => "objective-id",
                    "target-id" => "cm-2",
                    "status" => { "state" => "satisfied" }
                  },
                  "related-observations" => [ { "observation-uuid" => "obs-1" } ]
                }
              ]
            }
          ]
        }
      }
    end

    before do
      path = write_fixture(results_hash)
      described_class.new(document, path).parse
      @ctrl = document.reload.sar_controls.find_by(control_id: "cm-2")
      @fields = @ctrl.sar_control_fields.index_by(&:field_name)
    end

    it "creates a SarControl for cm-2" do
      expect(@ctrl).to be_present
    end

    it "populates control_status from target.status.state" do
      expect(@fields["control_status"]&.field_value).to eq("Implemented")
    end

    it "preserves the canonical OSCAL state in 'result'" do
      expect(@fields["result"]&.field_value).to eq("satisfied")
    end

    it "extracts subject_asset from observation remarks" do
      expect(@ctrl.subject_asset).to eq("aws.default")
    end

    it "populates date from observation.collected" do
      expect(@fields["date"]&.field_value).to eq("2026-04-15T13:31:35Z")
    end

    it "populates test_text from observation methods" do
      expect(@fields["test_text"]&.field_value).to eq("AUTOMATED")
    end
  end

  describe "SAR -> SAP -> SSP enrichment chain" do
    let(:ssp) { create(:ssp_document) }
    let(:sap) { create(:sap_document, ssp_document: ssp) }
    let(:document) { create(:sar_document, :oscal_import, status: "processing", sap_document: sap) }

    before do
      ssp_ctrl = ssp.ssp_controls.create!(control_id: "cm-2", title: "Baseline Configuration", row_order: 0)
      ssp_ctrl.ssp_control_fields.create!(field_name: "responsible_entities", field_value: "Platform Engineering Team")
      ssp_ctrl.ssp_control_fields.create!(field_name: "implementation_statement",
                                          field_value: "Terraform-managed AWS account baseline.")
      ssp_ctrl.ssp_control_fields.create!(field_name: "notes",
                                          field_value: "Risk accepted; documented in CAB record 1234.")
    end

    it "pulls responsibility, implementation, and impact_statement from the linked SAP -> SSP" do
      file_hash = {
        "assessment-results" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "SAR with SAP link", "oscal-version" => "1.1.2" },
          "results" => [
            {
              "uuid" => SecureRandom.uuid,
              "title" => "Result",
              "start" => Time.current.iso8601,
              "findings" => [
                {
                  "uuid" => SecureRandom.uuid,
                  "title" => "Finding",
                  "target" => { "type" => "control", "target-id" => "cm-2",
                                "status" => { "state" => "satisfied" } }
                }
              ]
            }
          ]
        }
      }

      path = write_fixture(file_hash)
      described_class.new(document, path).parse

      ctrl = document.reload.sar_controls.find_by(control_id: "cm-2")
      fields = ctrl.sar_control_fields.index_by(&:field_name)
      expect(fields["responsibility"]&.field_value).to eq("Platform Engineering Team")
      expect(fields["implementation"]&.field_value).to eq("Terraform-managed AWS account baseline.")
      expect(fields["impact_statement"]&.field_value).to eq("Risk accepted; documented in CAB record 1234.")
    end
  end
end
