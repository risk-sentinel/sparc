require "rails_helper"

RSpec.describe ProjectMembership, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:user_name) }
    it { is_expected.to validate_presence_of(:role) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:project) }
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:role)
        .backed_by_column_of_type(:string)
        .with_values(
          authorizing_official: "authorizing_official",
          system_owner: "system_owner",
          ciso: "ciso",
          isso: "isso",
          project_member: "project_member",
          assessor: "assessor",
          view_only: "view_only"
        )
    }
  end

  describe "#role_label" do
    it "returns a human-readable label for the role" do
      membership = build(:project_membership, role: "authorizing_official")
      expect(membership.role_label).to eq("Authorizing Official (AO)")
    end

    it "returns ISSO label" do
      membership = build(:project_membership, role: "isso")
      expect(membership.role_label).to eq("ISSO")
    end
  end

  describe "ROLES constant" do
    it "lists all 7 project-level RMF roles" do
      expect(ProjectMembership::ROLES).to contain_exactly(
        "authorizing_official", "system_owner", "ciso", "isso",
        "project_member", "assessor", "view_only"
      )
    end
  end
end
