# frozen_string_literal: true

require "rails_helper"

# Every authorization decision in SPARC funnels through these three lookups, and
# until #1044 consolidated them they shared a copy-pasted JSONB predicate.
#
# WHY THIS FILE EXISTS: mutation-checking that consolidation showed the unit
# suite barely noticed it. Deleting the permission filter entirely — so ANY role
# would grant ANY permission — turned exactly ONE example red out of 136 across
# spec/security and spec/models/user_spec.rb. Request specs would have caught it
# eventually, but the predicate itself had almost no direct coverage, which for
# the funnel every access check passes through is the wrong place to be thin.
#
# These examples pin SPECIFICITY (the key matters), SCOPE (the boundary matters)
# and the two authority short-circuits.
RSpec.describe "User permission lookups" do
  let(:user) { create(:user, admin: false) }
  let(:boundary) { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  def role_granting(*keys, scope: "authorization_boundary")
    Role.create!(name: "role_#{SecureRandom.hex(4)}", display_name: "Test Role",
                 scope: scope, permissions: keys.index_with { true })
  end

  describe "the key matters" do
    it "grants the permission the role actually carries" do
      user.user_roles.create!(role: role_granting("ssp.write"), authorization_boundary: boundary)

      expect(user.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(true)
    end

    # The mutation that survived: a lookup matching any role rather than one
    # granting the key would pass the example above and fail only here.
    it "does NOT grant a different permission from the same role" do
      user.user_roles.create!(role: role_granting("ssp.write"), authorization_boundary: boundary)

      expect(user.has_permission?("catalogs.approve", authorization_boundary_id: boundary.id)).to be(false)
      expect(user.has_permission?("ssp.read", authorization_boundary_id: boundary.id)).to be(false)
    end

    it "does not grant anything when the user holds no role at all" do
      expect(user.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(false)
      expect(user.has_any_permission?("ssp.write")).to be(false)
    end
  end

  describe "the boundary matters" do
    it "does not leak a boundary-scoped grant to another boundary" do
      user.user_roles.create!(role: role_granting("ssp.write"), authorization_boundary: boundary)

      expect(user.has_permission?("ssp.write", authorization_boundary_id: other_boundary.id)).to be(false)
    end

    it "applies an instance-scoped grant everywhere" do
      user.user_roles.create!(role: role_granting("ssp.write", scope: "instance"),
                              authorization_boundary: nil)

      expect(user.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(true)
      expect(user.has_permission?("ssp.write")).to be(true)
    end

    # has_any_permission? answers "anywhere at all", which is a different
    # question from has_permission? with no boundary — that one means
    # "instance-wide". A boundary-scoped grant satisfies the first, not the second.
    it "distinguishes 'anywhere' from 'instance-wide'" do
      user.user_roles.create!(role: role_granting("ssp.write"), authorization_boundary: boundary)

      expect(user.has_any_permission?("ssp.write")).to be(true)
      expect(user.has_permission?("ssp.write")).to be(false)
    end
  end

  describe "authority short-circuits" do
    it "the break-glass account passes without holding any role" do
      expect(create(:user, admin: true).has_permission?("catalogs.approve")).to be(true)
    end

    it "an instance administrator passes without holding the specific permission" do
      role = Role.create!(name: "instance_admin_#{SecureRandom.hex(4)}",
                          display_name: "Instance Administrator", scope: "instance",
                          permissions: { "admin.administer" => true })
      user.user_roles.create!(role: role, authorization_boundary: nil, source: "idp")

      expect(user.reload.has_permission?("catalogs.approve")).to be(true)
      expect(user.admin?).to be(false)
    end
  end
end
