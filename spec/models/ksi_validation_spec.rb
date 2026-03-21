# frozen_string_literal: true

require "rails_helper"

RSpec.describe KsiValidation, type: :model do
  describe "validations" do
    subject { build(:ksi_validation) }

    it { is_expected.to be_valid }

    it "requires an authorization_boundary" do
      subject.authorization_boundary = nil
      expect(subject).not_to be_valid
    end

    it "requires a catalog_control" do
      subject.catalog_control = nil
      expect(subject).not_to be_valid
    end

    it "validates status inclusion" do
      subject.status = "invalid_status"
      expect(subject).not_to be_valid
    end

    it "validates validation_method inclusion" do
      subject.validation_method = "invalid"
      expect(subject).not_to be_valid
    end

    it "allows nil validation_method" do
      subject.validation_method = nil
      expect(subject).to be_valid
    end

    it "enforces uniqueness of catalog_control per boundary" do
      existing = create(:ksi_validation)
      duplicate = build(:ksi_validation,
        authorization_boundary: existing.authorization_boundary,
        catalog_control: existing.catalog_control)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:catalog_control_id]).to be_present
    end

    it "allows same control in different boundaries" do
      existing = create(:ksi_validation)
      other_boundary = create(:authorization_boundary)
      different = build(:ksi_validation,
        authorization_boundary: other_boundary,
        catalog_control: existing.catalog_control)
      expect(different).to be_valid
    end
  end

  describe "UUID generation" do
    it "auto-generates a uuid on create" do
      validation = create(:ksi_validation)
      expect(validation.uuid).to be_present
      expect(validation.uuid).to match(/\A[0-9a-f-]{36}\z/)
    end
  end

  describe "scopes" do
    describe ".overdue" do
      it "returns validations past their due date" do
        overdue = create(:ksi_validation, next_validation_due: 1.day.ago)
        current = create(:ksi_validation, next_validation_due: 1.day.from_now)

        expect(KsiValidation.overdue).to include(overdue)
        expect(KsiValidation.overdue).not_to include(current)
      end
    end

    describe ".due_soon" do
      it "returns validations due within the specified days" do
        soon = create(:ksi_validation, next_validation_due: 3.days.from_now)
        far = create(:ksi_validation, next_validation_due: 30.days.from_now)

        expect(KsiValidation.due_soon(7)).to include(soon)
        expect(KsiValidation.due_soon(7)).not_to include(far)
      end
    end

    describe ".by_status" do
      it "filters by status" do
        passed = create(:ksi_validation, :passed)
        failed = create(:ksi_validation, :failed)

        expect(KsiValidation.by_status("passed")).to include(passed)
        expect(KsiValidation.by_status("passed")).not_to include(failed)
      end
    end

    describe ".by_theme" do
      it "filters by theme code" do
        family_a = create(:control_family, code: "IAM")
        family_b = create(:control_family, code: "MLA")
        control_a = create(:catalog_control, control_family: family_a)
        control_b = create(:catalog_control, control_family: family_b)
        val_a = create(:ksi_validation, catalog_control: control_a)
        val_b = create(:ksi_validation, catalog_control: control_b)

        expect(KsiValidation.by_theme("IAM")).to include(val_a)
        expect(KsiValidation.by_theme("IAM")).not_to include(val_b)
      end
    end
  end

  describe "#check_expiration" do
    it "marks passed validations as expired when overdue" do
      validation = build(:ksi_validation,
        status: "passed",
        next_validation_due: 1.day.ago)
      validation.save!
      expect(validation.status).to eq("expired")
    end

    it "does not expire failed validations" do
      validation = build(:ksi_validation,
        status: "failed",
        next_validation_due: 1.day.ago)
      validation.save!
      expect(validation.status).to eq("failed")
    end
  end

  describe "delegation" do
    it "delegates theme_code to control_family" do
      family = create(:control_family, code: "SVC")
      control = create(:catalog_control, control_family: family)
      validation = create(:ksi_validation, catalog_control: control)

      expect(validation.theme_code).to eq("SVC")
    end

    it "delegates ksi_id to catalog_control" do
      control = create(:catalog_control, control_id: "ksi-svc-01")
      validation = create(:ksi_validation, catalog_control: control)

      expect(validation.ksi_id).to eq("ksi-svc-01")
    end
  end
end
