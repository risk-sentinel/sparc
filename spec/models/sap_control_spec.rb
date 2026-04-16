require "rails_helper"

RSpec.describe SapControl, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:sap_document) }
    it { is_expected.to have_many(:sap_control_fields).dependent(:delete_all) }
    it { is_expected.to have_many(:sap_control_objectives).dependent(:delete_all) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:control_id) }
  end

  describe "#compute_control_family" do
    it "computes family from control_id" do
      control = create(:sap_control, control_id: "AC-1", control_family: nil)
      expect(control.control_family).to eq("AC")
    end

    it "preserves existing control_family" do
      control = create(:sap_control, control_id: "AC-1", control_family: "CUSTOM")
      expect(control.control_family).to eq("CUSTOM")
    end
  end

  describe "#to_hash" do
    let(:control) { create(:sap_control, control_id: "AC-2", assessment_method: "test") }

    it "returns a serializable hash" do
      hash = control.to_hash
      expect(hash[:control_id]).to eq("AC-2")
      expect(hash[:assessment_method]).to eq("test")
      expect(hash[:fields]).to be_an(Array)
    end
  end

  describe "#objective_status_rollup" do
    let(:control) { create(:sap_control) }

    it "returns not_assessed when no objectives exist" do
      expect(control.objective_status_rollup).to eq("not_assessed")
    end

    it "returns failed when any objective is failed (failed beats in-progress)" do
      create(:sap_control_objective, sap_control: control, status: "passing")
      create(:sap_control_objective, sap_control: control, status: "in-progress")
      create(:sap_control_objective, sap_control: control, status: "failed")
      expect(control.reload.objective_status_rollup).to eq("failed")
    end

    it "returns in-progress when no failures and any in-progress" do
      create(:sap_control_objective, sap_control: control, status: "in-progress")
      create(:sap_control_objective, sap_control: control, status: "passing")
      expect(control.reload.objective_status_rollup).to eq("in-progress")
    end

    it "returns pending when only pending objectives remain" do
      create(:sap_control_objective, sap_control: control, status: "pending")
      create(:sap_control_objective, sap_control: control, status: "passing")
      expect(control.reload.objective_status_rollup).to eq("pending")
    end

    it "returns passing when all are passing or not_applicable" do
      create(:sap_control_objective, sap_control: control, status: "passing")
      create(:sap_control_objective, sap_control: control, status: "not_applicable")
      expect(control.reload.objective_status_rollup).to eq("passing")
    end
  end

  describe "#aggregate_objective_text" do
    let(:control) { create(:sap_control, objective: "legacy text blob") }

    it "returns the legacy text when no objective records exist" do
      expect(control.aggregate_objective_text).to eq("legacy text blob")
    end

    it "joins objective prose with labels when records exist" do
      create(:sap_control_objective, sap_control: control,
                                     label: "AC-01a.[01]", prose: "first objective", row_order: 0)
      create(:sap_control_objective, sap_control: control,
                                     label: "AC-01a.[02]", prose: "second objective", row_order: 1)
      expect(control.reload.aggregate_objective_text).to eq(
        "[AC-01a.[01]] first objective\n\n[AC-01a.[02]] second objective"
      )
    end
  end
end
