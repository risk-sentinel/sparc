# frozen_string_literal: true

require "rails_helper"

# #707 / #919 — boundary roster membership grants the matching permissions on
# that boundary, and only on that boundary.
#
# ── Why these specs seed roles explicitly ──────────────────────────────────
#
# The test database has NO seeded Role rows. Without the roles below,
# `canonical_role_for` finds nothing, no grant is created, and every expectation
# about "has permission" would be asserting against an app where the feature
# does nothing — passing for the wrong reason. That is not hypothetical: the
# first manual probe of this feature returned false for everything and looked
# like a broken implementation, when it was a missing fixture.
RSpec.describe BoundaryMembershipRoleSync do
  # Mirrors the seeded catalog closely enough to exercise the mapping: two
  # boundary roles with different write authority, plus an instance role to
  # prove instance grants are never produced.
  let!(:isso_role) do
    Role.create!(name: "isso", display_name: "ISSO", scope: "authorization_boundary",
                 permissions: { "ssp.read" => true, "ssp.write" => true,
                                "poam.read" => true, "poam.write" => true })
  end
  let!(:view_only_role) do
    Role.create!(name: "view_only", display_name: "View Only", scope: "authorization_boundary",
                 permissions: { "ssp.read" => true, "poam.read" => true })
  end
  let!(:ao_role) do
    Role.create!(name: "ao", display_name: "Authorizing Official", scope: "authorization_boundary",
                 permissions: { "poam.read" => true, "poam.write" => true, "amendment.approve" => true })
  end

  let(:user)     { create(:user) }
  let(:boundary) { create(:authorization_boundary) }

  def join(bound, role, as: user)
    AuthorizationBoundaryMembership.create!(
      authorization_boundary: bound, user: as,
      user_name: as.display_name.presence || "Member", user_email: as.email, role: role
    )
  end

  describe "joining a boundary" do
    it "grants the role's permissions on that boundary" do
      join(boundary, "isso")

      expect(user.reload.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(true)
      expect(user.has_permission?("poam.write", authorization_boundary_id: boundary.id)).to be(true)
    end

    it "grants NOTHING instance-wide" do
      join(boundary, "isso")

      expect(user.reload.has_permission?("ssp.write")).to be(false),
        "A boundary member must never gain instance-wide authority — an instance grant " \
        "satisfies the check on EVERY boundary."
    end

    it "grants nothing on a boundary they have not joined" do
      other = create(:authorization_boundary)
      join(boundary, "isso")

      expect(user.reload.has_permission?("ssp.write", authorization_boundary_id: other.id)).to be(false)
    end

    it "marks the grant as membership-derived" do
      join(boundary, "isso")

      expect(UserRole.where(user: user).pluck(:source)).to eq(%w[membership])
    end

    it "creates a BOUNDARY-scoped grant, never an instance one" do
      join(boundary, "isso")

      expect(UserRole.where(user: user).pluck(:authorization_boundary_id)).to eq([ boundary.id ])
    end
  end

  # The property the owner called out: same person, different authority per
  # boundary. This is what makes AO/SO/ISSO boundary roles rather than titles.
  describe "different roles on different boundaries" do
    let(:read_write_boundary) { create(:authorization_boundary) }
    let(:read_only_boundary)  { create(:authorization_boundary) }

    before do
      join(read_write_boundary, "isso")
      join(read_only_boundary, "view_only")
      user.reload
    end

    it "writes where they are ISSO" do
      expect(user.has_permission?("ssp.write", authorization_boundary_id: read_write_boundary.id)).to be(true)
    end

    it "cannot write where they are view-only" do
      expect(user.has_permission?("ssp.write", authorization_boundary_id: read_only_boundary.id)).to be(false)
    end

    it "still reads where they are view-only" do
      expect(user.has_permission?("ssp.read", authorization_boundary_id: read_only_boundary.id)).to be(true)
    end

    it "holds two separate boundary-scoped grants" do
      expect(UserRole.where(user: user).count).to eq(2)
      expect(UserRole.where(user: user, authorization_boundary_id: nil)).to be_empty
    end
  end

  # The case a naive find_or_create would get wrong: it would ADD the new grant
  # and leave the old one, so demoting someone to view_only would silently keep
  # their write access.
  describe "changing a member's role" do
    it "revokes the old permissions rather than accumulating" do
      membership = join(boundary, "isso")
      expect(user.reload.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(true)

      membership.update!(role: "view_only")

      expect(user.reload.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(false)
      expect(UserRole.where(user: user).count).to eq(1)
    end
  end

  describe "removing a member" do
    it "revokes the grant" do
      membership = join(boundary, "isso")
      membership.destroy!

      expect(user.reload.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(false)
      expect(UserRole.where(user: user)).to be_empty
    end

    # The reason the `source` column exists. A roster edit must never revoke an
    # administrator's deliberate assignment.
    it "leaves a manually-assigned grant untouched" do
      manual = UserRole.create!(user: user, role: ao_role,
                                authorization_boundary: boundary, source: "manual")
      membership = join(boundary, "isso")
      membership.destroy!

      expect(UserRole.where(user: user)).to contain_exactly(manual)
      expect(user.reload.has_permission?("amendment.approve", authorization_boundary_id: boundary.id)).to be(true)
    end
  end

  describe "role-name mapping between the two vocabularies" do
    # The roster vocabulary and the canonical Role catalog are not identical.
    # Four names match exactly; three need translating.
    {
      "authorizing_official" => "ao",
      "isso"                 => "isso",
      "view_only"            => "view_only"
    }.each do |membership_role, canonical_name|
      it "maps #{membership_role} to #{canonical_name}" do
        expect(described_class.canonical_role_for(membership_role)&.name).to eq(canonical_name)
      end
    end

    it "returns nil for a custom role with no canonical counterpart" do
      expect(described_class.canonical_role_for("chief_vibes_officer")).to be_nil
    end

    # Fail closed: an operator can invent a role via SPARC_AUTH_BOUNDARY_ROLES,
    # and inventing permissions for it would be worse than granting none.
    it "grants nothing for an unmapped role, and does not raise" do
      allow(Rails.logger).to receive(:warn)
      membership = AuthorizationBoundaryMembership.new(
        authorization_boundary: boundary, user: user,
        user_name: "Member", user_email: user.email, role: "isso"
      )
      membership.save!
      membership.update_column(:role, "chief_vibes_officer") # bypass role validation

      expect { described_class.sync!(membership) }.not_to raise_error
      expect(user.reload.has_permission?("ssp.write", authorization_boundary_id: boundary.id)).to be(false)
      expect(Rails.logger).to have_received(:warn).with(/maps to no canonical Role/)
    end
  end

  describe "a roster entry with no linked user" do
    it "is a no-op rather than an error" do
      membership = AuthorizationBoundaryMembership.create!(
        authorization_boundary: boundary, user: nil,
        user_name: "Not Yet Provisioned", user_email: "pending@example.gov", role: "isso"
      )

      expect { described_class.sync!(membership) }.not_to raise_error
      expect(UserRole.count).to eq(0)
    end
  end

  describe "idempotency" do
    it "produces the same state when synced repeatedly" do
      membership = join(boundary, "isso")

      3.times { described_class.sync!(membership) }

      expect(UserRole.where(user: user).count).to eq(1)
    end
  end
end
