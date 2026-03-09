# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserRole, type: :model do
  describe "validations" do
    subject { build(:user_role) }

    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:role) }
    it { is_expected.to belong_to(:authorization_boundary).optional }

    it "validates uniqueness scoped to role and authorization boundary" do
      existing = create(:user_role)
      duplicate = build(:user_role, user: existing.user, role: existing.role, authorization_boundary_id: existing.authorization_boundary_id)
      expect(duplicate).not_to be_valid
    end
  end

  describe "role_scope_matches_authorization_boundary" do
    let(:instance_role) { create(:role, scope: "instance") }
    let(:boundary_role) { create(:role, :authorization_boundary_scoped) }
    let(:authorization_boundary) { create(:authorization_boundary) }
    let(:user) { create(:user) }

    it "allows instance roles without an authorization boundary" do
      ur = build(:user_role, user: user, role: instance_role, authorization_boundary: nil)
      expect(ur).to be_valid
    end

    it "rejects instance roles with an authorization boundary" do
      ur = build(:user_role, user: user, role: instance_role, authorization_boundary: authorization_boundary)
      expect(ur).not_to be_valid
      expect(ur.errors[:role]).to include("is instance-scoped and cannot be assigned to an authorization boundary")
    end

    it "allows authorization boundary roles with an authorization boundary" do
      ur = build(:user_role, user: user, role: boundary_role, authorization_boundary: authorization_boundary)
      expect(ur).to be_valid
    end

    it "rejects authorization boundary roles without an authorization boundary" do
      ur = build(:user_role, user: user, role: boundary_role, authorization_boundary: nil)
      expect(ur).not_to be_valid
      expect(ur.errors[:role]).to include("is authorization boundary-scoped and requires an authorization boundary")
    end
  end
end
