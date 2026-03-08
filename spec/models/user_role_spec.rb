# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserRole, type: :model do
  describe "validations" do
    subject { build(:user_role) }

    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:role) }
    it { is_expected.to belong_to(:project).optional }

    it "validates uniqueness scoped to role and project" do
      existing = create(:user_role)
      duplicate = build(:user_role, user: existing.user, role: existing.role, project_id: existing.project_id)
      expect(duplicate).not_to be_valid
    end
  end

  describe "role_scope_matches_project" do
    let(:instance_role) { create(:role, scope: "instance") }
    let(:project_role) { create(:role, :project_scoped) }
    let(:project) { create(:project) }
    let(:user) { create(:user) }

    it "allows instance roles without a project" do
      ur = build(:user_role, user: user, role: instance_role, project: nil)
      expect(ur).to be_valid
    end

    it "rejects instance roles with a project" do
      ur = build(:user_role, user: user, role: instance_role, project: project)
      expect(ur).not_to be_valid
      expect(ur.errors[:role]).to include("is instance-scoped and cannot be assigned to a project")
    end

    it "allows project roles with a project" do
      ur = build(:user_role, user: user, role: project_role, project: project)
      expect(ur).to be_valid
    end

    it "rejects project roles without a project" do
      ur = build(:user_role, user: user, role: project_role, project: nil)
      expect(ur).not_to be_valid
      expect(ur.errors[:role]).to include("is project-scoped and requires a project")
    end
  end
end
