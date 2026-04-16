require "rails_helper"

RSpec.describe SarFinding, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:sar_result) }
    it { is_expected.to belong_to(:sar_control_objective).optional }
    it { is_expected.to have_many(:sar_finding_observations).dependent(:delete_all) }
    it { is_expected.to have_many(:sar_observations).through(:sar_finding_observations) }
    it { is_expected.to have_many(:sar_finding_risks).dependent(:delete_all) }
    it { is_expected.to have_many(:sar_risks).through(:sar_finding_risks) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:uuid) }
  end

  describe "objective linkage" do
    it "is valid without a sar_control_objective (control-level finding)" do
      finding = build(:sar_finding, sar_control_objective: nil)
      expect(finding).to be_valid
    end

    it "links to a sar_control_objective when set" do
      objective = create(:sar_control_objective)
      finding   = create(:sar_finding, sar_control_objective: objective)
      expect(finding.sar_control_objective).to eq(objective)
    end

    it "does not delete a finding when its objective is destroyed (nullify)" do
      objective = create(:sar_control_objective)
      finding   = create(:sar_finding, sar_control_objective: objective)
      objective.destroy!
      expect(SarFinding.find_by(id: finding.id)).to be_present
      expect(finding.reload.sar_control_objective_id).to be_nil
    end
  end
end
