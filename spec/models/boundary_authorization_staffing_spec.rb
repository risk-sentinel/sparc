# frozen_string_literal: true

require "rails_helper"

# #1040 Part 2b — a boundary cannot be AUTHORIZED without the people who are
# accountable for it.
#
# Before this, a boundary with ZERO members was valid, could reach
# `status: authorized`, and would export an SSP. SPARC enforced separation of
# duties at the moment of an ACTION and was silent at the moment of STAFFING.
RSpec.describe "staffing gate for authorization (#1040)" do
  let(:boundary) { create(:authorization_boundary, status: "draft") }

  def staff(*roles)
    roles.each do |role|
      create(:authorization_boundary_membership, authorization_boundary: boundary, role: role)
    end
    boundary.reload
  end

  describe "the transition into authorized" do
    it "is refused with no roster at all" do
      boundary.status = "authorized"

      expect(boundary).not_to be_valid
      expect(boundary.errors[:status].join).to match(/cannot be authorized without/)
    end

    it "names exactly which roles are missing" do
      staff("system_owner")
      boundary.status = "authorized"
      boundary.valid?

      message = boundary.errors[:status].join
      expect(message).to include("Authorizing Official")
      expect(message).to include("Isso")
      expect(message).not_to include("System Owner")
    end

    it "is allowed once AO, System Owner and ISSO are all on the roster" do
      staff("authorizing_official", "system_owner", "isso")
      boundary.status = "authorized"

      expect(boundary).to be_valid
    end

    # Both assignment paths count. Reading only one is how a person added
    # through admin becomes invisible on the boundary screen (#770 bug 3).
    it "counts a role granted through user_roles, not only through memberships" do
      role = Role.find_or_create_by!(name: "isso") do |r|
        r.display_name = "ISSO"
        r.scope = "authorization_boundary"
      end
      create(:user_role, user: create(:user), role: role, authorization_boundary: boundary)
      staff("authorizing_official", "system_owner")

      boundary.status = "authorized"

      expect(boundary).to be_valid
    end
  end

  # The in-memory case, which the first implementation got wrong: `pluck` issues
  # a query and cannot see unsaved children, so staffing and authorizing in ONE
  # save failed spuriously — the most natural thing a caller would write.
  it "counts memberships built in the same save, not only persisted ones" do
    AuthorizationBoundary::REQUIRED_ROLES_FOR_AUTHORIZATION.each do |role|
      boundary.authorization_boundary_memberships.build(
        role: role, user_name: "Someone", user_email: "someone@example.gov"
      )
    end
    boundary.status = "authorized"

    expect(boundary).to be_valid
  end

  describe "what the gate deliberately does NOT block" do
    # A boundary is not trapped by staffing it lost. An already-authorized
    # boundary whose ISSO leaves must stay editable, or the gate punishes the
    # records it exists to protect.
    it "allows editing an already-authorized boundary that is now understaffed" do
      staff("authorizing_official", "system_owner", "isso")
      boundary.update!(status: "authorized")
      boundary.authorization_boundary_memberships.destroy_all

      boundary.reload.name = "Renamed while understaffed"

      expect(boundary).to be_valid
    end

    it "allows draft, active and deauthorized with no roster" do
      %w[draft active deauthorized].each do |status|
        boundary.status = status
        expect(boundary).to be_valid, "#{status} should not require staffing"
      end
    end
  end
end
