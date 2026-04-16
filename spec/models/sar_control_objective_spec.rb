require "rails_helper"

RSpec.describe SarControlObjective, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:sar_control) }
    it { is_expected.to have_many(:sar_findings).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:sar_control_objective) }

    it { is_expected.to validate_presence_of(:objective_id) }
    it { is_expected.to validate_presence_of(:uuid) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SarControlObjective::OBJECTIVE_STATUSES) }

    it "enforces objective_id uniqueness within a sar_control" do
      control = create(:sar_control)
      create(:sar_control_objective, sar_control: control, objective_id: "ac-1_obj.a-1")
      duplicate = build(:sar_control_objective, sar_control: control, objective_id: "ac-1_obj.a-1")
      expect(duplicate).not_to be_valid
    end
  end
end
