require "rails_helper"

RSpec.describe SarControl, type: :model do
  subject { build(:sar_control) }

  describe "associations" do
    it { is_expected.to belong_to(:sar_document) }
    it { is_expected.to have_many(:sar_control_fields).dependent(:delete_all) }
  end

  describe "scopes" do
    it ".in_section filters by section" do
      doc = create(:sar_document)
      c1 = create(:sar_control, sar_document: doc, section: "Sheet1")
      create(:sar_control, sar_document: doc, section: "Sheet2", control_id: "IA-1")
      expect(SarControl.in_section("Sheet1")).to include(c1)
    end

    it ".boundary_findings filters controls without subject_asset" do
      doc = create(:sar_document)
      c1 = create(:sar_control, sar_document: doc, subject_asset: nil)
      create(:sar_control, sar_document: doc, subject_asset: "web-server", control_id: "IA-2")
      expect(SarControl.boundary_findings).to include(c1)
    end
  end

  describe "#compute_control_family" do
    it "extracts family prefix from control_id before save" do
      control = create(:sar_control, control_id: "AC-05")
      expect(control.control_family).to eq("AC")
    end

    it "handles nil control_id gracefully" do
      control = create(:sar_control, control_id: nil)
      expect(control.control_family).to be_nil
    end
  end

  describe "#to_hash" do
    it "returns a hash including control data and fields" do
      control = create(:sar_control)
      create(:sar_control_field, sar_control: control, field_name: "result", field_value: "Pass")
      result = control.to_hash
      expect(result).to include(:control_id, :title, :section, :fields)
      expect(result[:fields].first).to include(field_name: "result", field_value: "Pass")
    end
  end
end
