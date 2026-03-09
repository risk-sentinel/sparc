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
      field = build(:ssp_control_field, field_name: "status")
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
      expect(SspControlField::EDITABLE_FIELDS).to include("status")
    end

    it "defines VALID_STATUSES" do
      expect(SspControlField::VALID_STATUSES).to include("Implemented", "Deferred")
    end
  end
end
