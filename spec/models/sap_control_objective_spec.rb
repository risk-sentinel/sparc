require "rails_helper"

RSpec.describe SapControlObjective, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:sap_control) }
  end

  describe "validations" do
    subject { build(:sap_control_objective) }

    it { is_expected.to validate_presence_of(:objective_id) }
    it { is_expected.to validate_presence_of(:uuid) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SapControlObjective::OBJECTIVE_STATUSES) }

    it "enforces objective_id uniqueness within a sap_control" do
      control = create(:sap_control)
      create(:sap_control_objective, sap_control: control, objective_id: "ac-1_obj.a-1")
      duplicate = build(:sap_control_objective, sap_control: control, objective_id: "ac-1_obj.a-1")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:objective_id]).to include("has already been taken")
    end

    it "allows the same objective_id under a different sap_control" do
      a = create(:sap_control)
      b = create(:sap_control)
      create(:sap_control_objective, sap_control: a, objective_id: "ac-1_obj.a-1")
      sibling = build(:sap_control_objective, sap_control: b, objective_id: "ac-1_obj.a-1")
      expect(sibling).to be_valid
    end
  end

  describe "scopes" do
    let(:control) { create(:sap_control) }
    let!(:failing)        { create(:sap_control_objective, sap_control: control, status: "failed") }
    let!(:passing)        { create(:sap_control_objective, sap_control: control, status: "passing") }
    let!(:in_progress)    { create(:sap_control_objective, sap_control: control, status: "in-progress") }
    let!(:pending)        { create(:sap_control_objective, sap_control: control, status: "pending") }
    let!(:not_applicable) { create(:sap_control_objective, sap_control: control, status: "not_applicable") }

    it { expect(described_class.failing).to include(failing) }
    it { expect(described_class.passing).to include(passing) }
    it { expect(described_class.in_progress).to include(in_progress) }
    it { expect(described_class.pending).to include(pending) }
    it { expect(described_class.not_applicable).to include(not_applicable) }
  end
end
