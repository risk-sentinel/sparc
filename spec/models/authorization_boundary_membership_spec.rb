require "rails_helper"

RSpec.describe AuthorizationBoundaryMembership, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:user_name) }
    it { is_expected.to validate_presence_of(:role) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:authorization_boundary) }
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
      membership = build(:authorization_boundary_membership, role: "authorizing_official")
      expect(membership.role_label).to eq("Authorizing Official (AO)")
    end

    it "returns ISSO label" do
      membership = build(:authorization_boundary_membership, role: "isso")
      expect(membership.role_label).to eq("ISSO")
    end
  end

  describe "roles" do
    it "has 7 default authorization-boundary-level RMF roles" do
      expect(AuthorizationBoundaryMembership::DEFAULT_ROLES).to contain_exactly(
        "authorizing_official", "system_owner", "ciso", "isso",
        "project_member", "assessor", "view_only"
      )
    end

    it "returns available roles from SparcConfig" do
      roles = AuthorizationBoundaryMembership.available_roles
      expect(roles).to be_an(Array)
      expect(roles).not_to be_empty
    end
  end
end
