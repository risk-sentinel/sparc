require "rails_helper"

RSpec.describe SspControlField, type: :model do
  subject { build(:ssp_control_field) }

  describe "associations" do
    it { is_expected.to belong_to(:ssp_control) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:field_name) }
  end

  describe "editable flag" do
    it "sets editable to true for fields in EDITABLE_FIELDS" do
      field = build(:ssp_control_field, field_name: "notes")
      field.valid?
      expect(field.editable).to be true
    end

    it "sets editable to false for fields not in EDITABLE_FIELDS" do
      field = build(:ssp_control_field, field_name: "inherited_from")
      field.valid?
      expect(field.editable).to be false
    end
  end

  describe "constants" do
    it "defines EDITABLE_FIELDS" do
      expect(SspControlField::EDITABLE_FIELDS).to include("notes")
    end

    # #1312 — answered per statement item now, or retired; a stored row is
    # never editable again.
    it "retires the control-level status, origination, roles and completion" do
      expect(SspControlField::RETIRED_FIELDS).to contain_exactly(
        "status", "control_application", "coverage_level", "control_type", "responsible_entities", "expected_completion"
      )
      expect(SspControlField::EDITABLE_FIELDS & SspControlField::RETIRED_FIELDS).to be_empty
      field = build(:ssp_control_field, field_name: "status")
      field.valid?
      expect(field.editable).to be false
    end

    it "defines VALID_STATUSES" do
      expect(SspControlField::VALID_STATUSES).to include("Implemented", "Deferred")
    end
  end
end
