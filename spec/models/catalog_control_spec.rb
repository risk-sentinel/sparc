require "rails_helper"

RSpec.describe CatalogControl, type: :model do
  describe "associations" do
    it "belongs to a control family" do
      control = build(:catalog_control)
      expect(control).to respond_to(:control_family)
    end
  end

  describe "validations" do
    it "requires control_id" do
      control = build(:catalog_control, control_id: nil)
      expect(control).not_to be_valid
      expect(control.errors[:control_id]).to include("can't be blank")
    end

    it "requires control_id to be unique within a family" do
      family = create(:control_family)
      create(:catalog_control, control_family: family, control_id: "ac-1")
      duplicate = build(:catalog_control, control_family: family, control_id: "ac-1")
      expect(duplicate).not_to be_valid
    end

    it "allows same control_id in different families" do
      family1 = create(:control_family)
      family2 = create(:control_family)
      create(:catalog_control, control_family: family1, control_id: "ac-1")
      control = build(:catalog_control, control_family: family2, control_id: "ac-1")
      expect(control).to be_valid
    end
  end

  describe "#family_code" do
    it "returns the family code" do
      family = create(:control_family, code: "AC")
      control = create(:catalog_control, control_family: family)
      expect(control.family_code).to eq("AC")
    end
  end

  describe "#guidance_present?" do
    it "returns false when guidance_data is empty" do
      control = build(:catalog_control, guidance_data: {})
      expect(control.guidance_present?).to be false
    end

    it "returns true when a guidance field has content" do
      control = build(:catalog_control, guidance_data: { "supplemental_guidance" => "Some guidance" })
      expect(control.guidance_present?).to be true
    end

    it "returns false when only non-guidance fields are present" do
      control = build(:catalog_control, guidance_data: { "statement" => "A statement" })
      expect(control.guidance_present?).to be false
    end
  end

  describe "#guidance_fields" do
    it "returns only populated guidance fields" do
      control = build(:catalog_control, guidance_data: {
        "supplemental_guidance" => "Guidance text",
        "related_controls" => "AC-2, AC-3",
        "statement" => "Statement text"
      })

      fields = control.guidance_fields
      expect(fields).to have_key("supplemental_guidance")
      expect(fields).to have_key("related_controls")
      expect(fields).not_to have_key("statement")
    end

    it "returns empty hash when no guidance data" do
      control = build(:catalog_control, guidance_data: {})
      expect(control.guidance_fields).to eq({})
    end
  end

  describe "GUIDANCE_FIELDS" do
    it "includes standard fields" do
      expect(CatalogControl::GUIDANCE_FIELDS).to include(
        "supplemental_guidance", "implementation_guidance", "check",
        "fix", "related_controls", "org_ref", "nist_references"
      )
    end
  end
end
