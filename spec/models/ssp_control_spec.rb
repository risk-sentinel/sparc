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
    # #911 — the shoulda `validate_uniqueness_of` matcher cannot express this
    # model any more, in either its case-sensitive or case_insensitive form.
    # It probes uniqueness by mutating the attribute and re-validating, but
    # canonicalisation runs in before_validation and rewrites whatever the
    # matcher just set, so its probes no longer mean what it assumes.
    #
    # Replaced with the two behavioural examples below, which assert the actual
    # contract — same control twice in one document is rejected, the same
    # control in a different document is allowed — rather than a proxy for it.
    # These are strictly stronger: they also pin the canonicalisation
    # interaction, which the matcher never covered.
    it "rejects a second spelling of a control the document already has" do
      document = create(:ssp_document)
      create(:ssp_control, ssp_document: document, control_id: "AC-02")
      duplicate = build(:ssp_control, ssp_document: document, control_id: "AC-2")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:control_id]).to be_present
    end

    it "still allows the same control in a different document" do
      create(:ssp_control, ssp_document: create(:ssp_document), control_id: "AC-02")
      other = build(:ssp_control, ssp_document: create(:ssp_document), control_id: "ac-2")

      expect(other).to be_valid
    end
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
