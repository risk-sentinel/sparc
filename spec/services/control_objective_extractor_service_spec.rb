require "rails_helper"

RSpec.describe ControlObjectiveExtractorService do
  describe ".objectives_for_control" do
    let(:catalog_json) do
      {
        "catalog" => {
          "groups" => [
            {
              "id" => "ac",
              "controls" => [
                {
                  "id" => "ac-1",
                  "title" => "Policy and Procedures",
                  "parts" => [
                    {
                      "id" => "ac-1_obj",
                      "name" => "assessment-objective",
                      "parts" => [
                        {
                          "id" => "ac-1_obj.a",
                          "name" => "assessment-objective",
                          "parts" => [
                            {
                              "id" => "ac-1_obj.a-1",
                              "name" => "assessment-objective",
                              "props" => [ { "name" => "label", "value" => "AC-01a.[01]" } ],
                              "prose" => "a policy is documented;"
                            },
                            {
                              "id" => "ac-1_obj.a-2",
                              "name" => "assessment-objective",
                              "props" => [ { "name" => "label", "value" => "AC-01a.[02]" } ],
                              "prose" => "the policy addresses purpose;"
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
    end

    it "returns leaf objectives with prose and labels" do
      result = described_class.objectives_for_control(catalog_json, "ac-1")
      ids = result.map { |o| o[:objective_id] }
      expect(ids).to include("ac-1_obj.a-1", "ac-1_obj.a-2")
    end

    it "preserves the parent_objective_id chain for nested leaves" do
      result = described_class.objectives_for_control(catalog_json, "ac-1")
      leaf = result.find { |o| o[:objective_id] == "ac-1_obj.a-1" }
      expect(leaf[:parent_objective_id]).to eq("ac-1_obj.a")
    end

    it "includes structural wrapper objectives in the output (no prose, no label)" do
      result = described_class.objectives_for_control(catalog_json, "ac-1")
      wrapper = result.find { |o| o[:objective_id] == "ac-1_obj" }
      expect(wrapper[:prose]).to be_nil
      expect(wrapper[:parent_objective_id]).to be_nil
    end

    it "assigns row_order in walk order" do
      result = described_class.objectives_for_control(catalog_json, "ac-1")
      expect(result.map { |o| o[:row_order] }).to eq((0...result.size).to_a)
    end

    it "returns [] when the catalog is blank" do
      expect(described_class.objectives_for_control(nil, "ac-1")).to eq([])
      expect(described_class.objectives_for_control({}, "ac-1")).to eq([])
    end

    it "returns [] when the control isn't in the catalog" do
      expect(described_class.objectives_for_control(catalog_json, "zz-99")).to eq([])
    end

    it "doesn't raise on a malformed catalog" do
      bad = { "catalog" => { "groups" => [ { "controls" => [ { "id" => "ac-1" } ] } ] } }
      expect { described_class.objectives_for_control(bad, "ac-1") }.not_to raise_error
    end

    it "matches case-insensitively" do
      result = described_class.objectives_for_control(catalog_json, "AC-1")
      expect(result).not_to be_empty
    end
  end

  describe "#backfill!" do
    let(:catalog_json) do
      {
        "catalog" => {
          "controls" => [
            {
              "id" => "ac-1",
              "parts" => [
                {
                  "id" => "ac-1_obj.a",
                  "name" => "assessment-objective",
                  "props" => [ { "name" => "label", "value" => "AC-01a" } ],
                  "prose" => "policy is documented"
                }
              ]
            }
          ]
        }
      }
    end

    context "when the SAP has a linked profile" do
      let(:profile) { create(:profile_document, resolved_catalog_json: catalog_json) }
      let(:document) { create(:sap_document, profile_document: profile) }

      it "creates objective records for each control" do
        create(:sap_control, sap_document: document, control_id: "ac-1")
        expect { described_class.new(document).backfill! }.to(
          change { SapControlObjective.where(objective_id: "ac-1_obj.a").count }.by(1)
        )
      end

      it "skips controls that already have objectives (idempotent)" do
        ctrl = create(:sap_control, sap_document: document, control_id: "ac-1")
        create(:sap_control_objective, sap_control: ctrl, objective_id: "ac-1_obj.a")
        expect { described_class.new(document).backfill! }
          .not_to(change { SapControlObjective.count })
      end

      it "clears the needs_reassociation flag once it inserts records" do
        document.update!(import_metadata: { "objective_backfill_status" => "needs_reassociation" })
        create(:sap_control, sap_document: document, control_id: "ac-1")
        described_class.new(document).backfill!
        expect(document.reload.import_metadata).not_to have_key("objective_backfill_status")
      end
    end

    context "when the SAP has no linked profile" do
      let(:document) { create(:sap_document, profile_document: nil) }

      it "flags the document as needs_reassociation" do
        create(:sap_control, sap_document: document, control_id: "ac-1")
        described_class.new(document).backfill!
        expect(document.reload.import_metadata["objective_backfill_status"])
          .to eq("needs_reassociation")
      end

      it "returns 0" do
        create(:sap_control, sap_document: document, control_id: "ac-1")
        expect(described_class.new(document).backfill!).to eq(0)
      end
    end

    context "with a SAR document" do
      let(:profile) { create(:profile_document, resolved_catalog_json: catalog_json) }
      let(:document) { create(:sar_document, profile_document: profile) }

      it "creates SarControlObjective records" do
        create(:sar_control, sar_document: document, control_id: "ac-1")
        expect { described_class.new(document).backfill! }.to(
          change { SarControlObjective.where(objective_id: "ac-1_obj.a").count }.by(1)
        )
      end
    end
  end
end
