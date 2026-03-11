require "rails_helper"

RSpec.describe SspControl, type: :model do
  subject { build(:ssp_control) }

  describe "associations" do
    it { is_expected.to belong_to(:ssp_document) }
    it { is_expected.to belong_to(:parent).class_name("SspControl").optional }
    it { is_expected.to have_many(:provider_statements).dependent(:destroy) }
    it { is_expected.to have_many(:ssp_control_fields).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:control_id).scoped_to(:ssp_document_id) }
  end

  describe "#provider_statement?" do
    it "returns false when parent_id is nil" do
      control = build(:ssp_control, parent_id: nil)
      expect(control.provider_statement?).to be false
    end

    it "returns true when parent_id is present" do
      parent = create(:ssp_control)
      child = create(:ssp_control, ssp_document: parent.ssp_document, parent: parent, control_id: nil)
      expect(child.provider_statement?).to be true
    end
  end

  describe "#to_hash" do
    it "returns a hash with control data and nested fields" do
      control = create(:ssp_control)
      create(:ssp_control_field, ssp_control: control, field_name: "status", field_value: "Implemented")
      result = control.to_hash
      expect(result).to include(:control_id, :title, :row_order, :fields, :provider_statements)
      expect(result[:fields].first).to include(field_name: "status", field_value: "Implemented")
    end
  end
end
