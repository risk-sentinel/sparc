require "rails_helper"

RSpec.describe SarControlField, type: :model do
  subject { build(:sar_control_field) }

  describe "associations" do
    it { is_expected.to belong_to(:sar_control) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:field_name) }
  end

  describe "editable flag" do
    it "sets editable to true for fields in EDITABLE_FIELDS" do
      field = build(:sar_control_field, field_name: "result")
      field.valid?
      expect(field.editable).to be true
    end

    it "sets editable to false for fields not in EDITABLE_FIELDS" do
      field = build(:sar_control_field, field_name: "paragraph")
      field.valid?
      expect(field.editable).to be false
    end
  end

  describe "cached result sync" do
    it "syncs cached_result on the parent control when result field is saved" do
      control = create(:sar_control)
      create(:sar_control_field, sar_control: control, field_name: "result", field_value: "Pass")
      expect(control.reload.cached_result).to eq("Pass")
    end
  end

  describe "constants" do
    it "defines EDITABLE_FIELDS" do
      expect(SarControlField::EDITABLE_FIELDS).to include("result", "notes_weakness", "recommended_fix")
    end

    it "defines RESULT_VALUES" do
      expect(SarControlField::RESULT_VALUES).to eq(%w[Pass Failed])
    end
  end
end
