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

  describe "BASELINE_LEVELS" do
    it "contains LOW, MODERATE, HIGH" do
      expect(CatalogControl::BASELINE_LEVELS).to eq(%w[LOW MODERATE HIGH])
    end

    it "is frozen" do
      expect(CatalogControl::BASELINE_LEVELS).to be_frozen
    end
  end

  describe "#baseline_levels" do
    it "parses comma-separated string into array" do
      control = build(:catalog_control, baseline_impact: "LOW, MODERATE, HIGH")
      expect(control.baseline_levels).to eq(%w[LOW MODERATE HIGH])
    end

    it "returns empty array for nil" do
      control = build(:catalog_control, baseline_impact: nil)
      expect(control.baseline_levels).to eq([])
    end

    it "handles extra whitespace" do
      control = build(:catalog_control, baseline_impact: "  LOW ,  HIGH  ")
      expect(control.baseline_levels).to eq(%w[LOW HIGH])
    end

    it "uppercases values" do
      control = build(:catalog_control, baseline_impact: "low, moderate")
      expect(control.baseline_levels).to eq(%w[LOW MODERATE])
    end
  end

  describe "#has_baseline_level?" do
    it "returns true when level is present" do
      control = build(:catalog_control, baseline_impact: "LOW, MODERATE")
      expect(control.has_baseline_level?("LOW")).to be true
    end

    it "returns false when level is absent" do
      control = build(:catalog_control, baseline_impact: "LOW")
      expect(control.has_baseline_level?("HIGH")).to be false
    end

    it "is case-insensitive" do
      control = build(:catalog_control, baseline_impact: "LOW")
      expect(control.has_baseline_level?("low")).to be true
    end
  end

  describe "#add_baseline_level" do
    it "adds a new level" do
      control = build(:catalog_control, baseline_impact: "LOW")
      control.add_baseline_level("MODERATE")
      expect(control.baseline_impact).to eq("LOW, MODERATE")
    end

    it "does not add duplicates" do
      control = build(:catalog_control, baseline_impact: "LOW, MODERATE")
      control.add_baseline_level("LOW")
      expect(control.baseline_impact).to eq("LOW, MODERATE")
    end

    it "handles nil starting value" do
      control = build(:catalog_control, baseline_impact: nil)
      control.add_baseline_level("HIGH")
      expect(control.baseline_impact).to eq("HIGH")
    end
  end

  describe "#remove_baseline_level" do
    it "removes a level" do
      control = build(:catalog_control, baseline_impact: "LOW, MODERATE, HIGH")
      control.remove_baseline_level("MODERATE")
      expect(control.baseline_impact).to eq("LOW, HIGH")
    end

    it "sets to nil when last level removed" do
      control = build(:catalog_control, baseline_impact: "LOW")
      control.remove_baseline_level("LOW")
      expect(control.baseline_impact).to be_nil
    end

    it "handles removing a level that is not present" do
      control = build(:catalog_control, baseline_impact: "LOW")
      control.remove_baseline_level("HIGH")
      expect(control.baseline_impact).to eq("LOW")
    end
  end

  describe "#effective_params_list" do
    let(:family) { create(:control_family, code: "AC") }

    it "returns own params when present" do
      parent = create(:catalog_control, control_family: family, control_id: "ac-1",
                       params_data: [ { "id" => "ac-1_prm_1", "label" => "personnel or roles" } ])
      expect(parent.effective_params_list).to eq(parent.params_list)
    end

    it "inherits referenced params from parent control for sub-controls" do
      create(:catalog_control, control_family: family, control_id: "ac-1",
             params_data: [
               { "id" => "ac-1_prm_1", "label" => "personnel or roles" },
               { "id" => "ac-1_prm_2", "label" => "frequency" }
             ])
      sub = create(:catalog_control, control_family: family, control_id: "ac-1a",
                   title: "Disseminates to {{ insert: param, ac-1_prm_1 }}:",
                   params_data: [])

      result = sub.effective_params_list
      expect(result.length).to eq(1)
      expect(result.first["id"]).to eq("ac-1_prm_1")
      expect(result.first["label"]).to eq("personnel or roles")
    end

    it "returns empty array when sub-control has no param references in title" do
      create(:catalog_control, control_family: family, control_id: "ac-1",
             params_data: [ { "id" => "ac-1_prm_1", "label" => "test" } ])
      sub = create(:catalog_control, control_family: family, control_id: "ac-1a",
                   title: "Plain title with no parameter references",
                   params_data: [])

      expect(sub.effective_params_list).to eq([])
    end

    it "returns only the referenced params, not all parent params" do
      create(:catalog_control, control_family: family, control_id: "ac-1",
             params_data: [
               { "id" => "ac-1_prm_1", "label" => "first" },
               { "id" => "ac-1_prm_2", "label" => "second" },
               { "id" => "ac-1_prm_3", "label" => "third" }
             ])
      sub = create(:catalog_control, control_family: family, control_id: "ac-1b.1",
                   title: "Policy {{ insert: param, ac-1_prm_2 }}; and",
                   params_data: [])

      result = sub.effective_params_list
      expect(result.length).to eq(1)
      expect(result.first["id"]).to eq("ac-1_prm_2")
    end

    it "includes select metadata from parent params" do
      create(:catalog_control, control_family: family, control_id: "ac-18.1",
             params_data: [
               { "id" => "ac-18.1_prm_1", "select" => { "how-many" => "one-or-more", "choice" => %w[users devices] } }
             ])
      sub = create(:catalog_control, control_family: family, control_id: "ac-18.1a",
                   title: "Protects {{ insert: param, ac-18.1_prm_1 }}",
                   params_data: [])

      result = sub.effective_params_list
      expect(result.first["select"]).to eq({ "how-many" => "one-or-more", "choice" => %w[users devices] })
    end
  end
end
