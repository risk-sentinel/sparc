require "rails_helper"

RSpec.describe SapControlField, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:sap_control) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:field_name) }
  end

  describe "#set_editable_flag" do
    it "marks editable fields as editable" do
      field = create(:sap_control_field, field_name: "objective")
      expect(field.editable).to be true
    end

    it "marks non-editable fields as not editable" do
      field = create(:sap_control_field, field_name: "implementation_description")
      expect(field.editable).to be false
    end
  end
end
