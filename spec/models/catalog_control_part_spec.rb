require "rails_helper"

RSpec.describe CatalogControlPart, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:catalog_control) }
  end

  describe "validations" do
    subject { build(:catalog_control_part) }

    it { is_expected.to validate_presence_of(:part_id) }
    it { is_expected.to validate_presence_of(:part_name) }
    it { is_expected.to validate_presence_of(:uuid) }

    it "validates uniqueness of part_id scoped to catalog_control" do
      existing = create(:catalog_control_part, part_id: "ac-1_smt.a")
      dup = build(:catalog_control_part, catalog_control: existing.catalog_control, part_id: "ac-1_smt.a")
      expect(dup).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:control) { create(:catalog_control) }
    let!(:smt)     { create(:catalog_control_part, catalog_control: control, part_name: "statement") }
    let!(:obj)     { create(:catalog_control_part, catalog_control: control, part_name: "assessment-objective") }
    let!(:guid)    { create(:catalog_control_part, catalog_control: control, part_name: "guidance") }

    it "filters by part_name via scopes when defined" do
      expect(CatalogControlPart.where(part_name: "statement")).to include(smt)
      expect(CatalogControlPart.where(part_name: "statement")).not_to include(obj, guid)
    end
  end
end
