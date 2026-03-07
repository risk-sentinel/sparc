# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  subject { build(:user) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active suspended deactivated]) }

    it "requires password to be at least 12 characters" do
      user = build(:user, password: "short", password_confirmation: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("must be at least 12 characters (NIST 800-63B)")
    end

    it "allows nil password (for OAuth-only users)" do
      user = build(:user, :oauth_only)
      expect(user).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:identities).dependent(:destroy) }
    it { is_expected.to have_many(:user_roles).dependent(:destroy) }
    it { is_expected.to have_many(:roles).through(:user_roles) }
    it { is_expected.to have_many(:audit_events).dependent(:nullify) }
  end

  describe "#normalize_email" do
    it "downcases and strips email before validation" do
      user = create(:user, email: "  Jane.Doe@AOL.com  ")
      expect(user.email).to eq("jane.doe@aol.com")
    end

    it "prevents duplicate emails with different casing" do
      create(:user, email: "jane.doe@aol.com")
      duplicate = build(:user, email: "Jane.Doe@AOL.com")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include("has already been taken")
    end
  end

  describe "#active?" do
    it "returns true for active users" do
      expect(build(:user, status: "active")).to be_active
    end

    it "returns false for suspended users" do
      expect(build(:user, status: "suspended")).not_to be_active
    end
  end

  describe "#has_role?" do
    let(:user) { create(:user) }
    let(:role) { create(:role, name: "isso") }

    it "returns false when user has no roles" do
      expect(user.has_role?("isso")).to be false
    end

    it "returns true when user has the role" do
      create(:user_role, user: user, role: role)
      expect(user.has_role?("isso")).to be true
    end

    it "returns true for admins regardless of roles" do
      admin = create(:user, :admin)
      expect(admin.has_role?("isso")).to be true
    end
  end

  describe "#display_label" do
    it "returns display_name when present" do
      user = build(:user, display_name: "Jane Doe")
      expect(user.display_label).to eq("Jane Doe")
    end

    it "returns full name when display_name is blank" do
      user = build(:user, display_name: nil, first_name: "Jane", last_name: "Doe")
      expect(user.display_label).to eq("Jane Doe")
    end

    it "returns email when no name is set" do
      user = build(:user, display_name: nil, first_name: nil, last_name: nil, email: "jane@example.com")
      expect(user.display_label).to eq("jane@example.com")
    end
  end

  describe "#record_sign_in!" do
    it "increments sign_in_count and sets last_sign_in_at" do
      user = create(:user, sign_in_count: 0)
      user.record_sign_in!(ip_address: "192.168.1.1")
      user.reload
      expect(user.sign_in_count).to eq(1)
      expect(user.last_sign_in_at).to be_present
      expect(user.last_sign_in_ip).to eq("192.168.1.1")
    end
  end
end
