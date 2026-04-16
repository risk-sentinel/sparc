require "rails_helper"

RSpec.describe OscalAssessmentPlanExportService do
  let(:sap) do
    create(:sap_document,
           name: "FY26 Assessment Plan",
           assessment_type: "annual",
           assessment_start: Date.new(2026, 4, 1),
           assessment_end: Date.new(2026, 4, 30))
  end

  before do
    create(:sap_control,
           sap_document: sap,
           control_id: "AC-1",
           title: "Access Control Policy",
           assessment_method: "examine",
           assessment_status: "planned",
           objective: "Verify AC-1 policy documentation exists")
    create(:sap_control,
           sap_document: sap,
           control_id: "AC-2",
           title: "Account Management",
           assessment_method: "test",
           assessment_status: "planned",
           test_case: "Check user account provisioning workflow")
  end

  describe "#export_unvalidated" do
    it "produces valid JSON with assessment-plan root key" do
      json = subject.export_unvalidated
      data = JSON.parse(json)

      expect(data).to have_key("assessment-plan")
      plan = data["assessment-plan"]
      expect(plan["metadata"]["title"]).to eq("FY26 Assessment Plan")
      expect(plan["metadata"]["oscal-version"]).to eq("1.1.2")
    end

    it "includes reviewed-controls with all control IDs" do
      json = subject.export_unvalidated
      plan = JSON.parse(json)["assessment-plan"]

      reviewed = plan["reviewed-controls"]
      control_ids = reviewed["control-selections"].flat_map { |s|
        s["include-controls"].map { |c| c["control-id"] }
      }

      expect(control_ids).to include("ac-1", "ac-2")
    end

    it "includes local-definitions with activities grouped by method" do
      json = subject.export_unvalidated
      plan = JSON.parse(json)["assessment-plan"]

      activities = plan.dig("local-definitions", "activities")
      expect(activities).to be_an(Array)
      expect(activities.length).to eq(2) # examine and test

      methods = activities.map { |a| a.dig("props", 0, "value") }
      expect(methods).to contain_exactly("EXAMINE", "TEST")
    end

    it "includes import-ssp reference" do
      json = subject.export_unvalidated
      plan = JSON.parse(json)["assessment-plan"]

      expect(plan["import-ssp"]).to have_key("href")
    end
  end

  describe "include-controls statement-ids" do
    it "emits statement-ids for controls with sap_control_objectives" do
      ctrl = sap.sap_controls.find_by(control_id: "AC-1")
      create(:sap_control_objective, sap_control: ctrl, objective_id: "ac-1_obj.a-1", row_order: 0)
      create(:sap_control_objective, sap_control: ctrl, objective_id: "ac-1_obj.a-2", row_order: 1)

      data = JSON.parse(subject.export_unvalidated)
      activity = data["assessment-plan"]["local-definitions"]["activities"]
                   .find { |a| a["props"].any? { |p| p["value"] == "EXAMINE" } }
      include_entry = activity["related-controls"]["control-selections"]
                              .first["include-controls"]
                              .find { |c| c["control-id"] == "ac-1" }

      expect(include_entry["statement-ids"]).to eq([ "ac-1_obj.a-1", "ac-1_obj.a-2" ])
    end

    it "omits statement-ids for controls without objectives" do
      data = JSON.parse(subject.export_unvalidated)
      ac2_activity = data["assessment-plan"]["local-definitions"]["activities"]
                       .find { |a| a["props"].any? { |p| p["value"] == "TEST" } }
      include_entry = ac2_activity["related-controls"]["control-selections"]
                                   .first["include-controls"].first
      expect(include_entry).not_to have_key("statement-ids")
    end
  end

  describe "#validation_result" do
    it "returns a result struct" do
      result = subject.validation_result
      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
      expect(result).to respond_to(:schema_version)
    end
  end

  subject { described_class.new(sap) }
end
