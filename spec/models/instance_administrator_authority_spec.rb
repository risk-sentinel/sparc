# frozen_string_literal: true

require "rails_helper"

# #1044 — instance-administrator AUTHORITY, separate from break-glass IDENTITY.
#
# The model the owner specified: the break-glass administrator is a dedicated
# ACCOUNT (sparc.admin@…). An ordinary user (clem.field@…) can be granted
# instance-administrator authority by the IdP, which revokes it on a time basis.
# SPARC honours the role the directory sends.
#
# Both directions throughout, and the ALLOW leg uses a permission-holding
# NON-ADMIN — an allow leg proved with an admin proves only that admins work,
# which was never in doubt.
RSpec.describe "instance-administrator authority (#1044)" do
  let(:break_glass) { create(:user, admin: true) }
  let(:ordinary)    { create(:user, admin: false) }

  let(:instance_admin_role) do
    Role.find_or_create_by!(name: "instance_admin") do |role|
      role.display_name = "Instance Administrator"
      role.scope        = "instance"
      role.permissions  = { "admin.administer" => true }
    end
  end

  def grant_instance_admin(user, source: "idp")
    user.user_roles.create!(role: instance_admin_role, authorization_boundary: nil, source: source)
    user.reload
  end

  describe "who holds authority" do
    it "the break-glass account does" do
      expect(break_glass.instance_administrator?).to be(true)
    end

    it "a NON-ADMIN granted the role does — this is the point of the issue" do
      grant_instance_admin(ordinary)

      expect(ordinary.admin?).to be(false), "the allow leg must not be an admin"
      expect(ordinary.instance_administrator?).to be(true)
    end

    it "an ordinary user without the role does NOT" do
      expect(ordinary.instance_administrator?).to be(false)
    end

    # The role is instance-scoped for a reason: the same permission attached to
    # one boundary would be boundary-local power, not instance-wide authority.
    it "a boundary-scoped grant of the same permission does NOT confer it" do
      boundary = create(:authorization_boundary)
      scoped = Role.create!(name: "boundary_pseudo_admin", display_name: "Boundary Pseudo Admin",
                            scope: "authorization_boundary",
                            permissions: { "admin.administer" => true })
      ordinary.user_roles.create!(role: scoped, authorization_boundary: boundary, source: "idp")

      expect(ordinary.reload.instance_administrator?).to be(false)
    end
  end

  describe "authority carries the capabilities, not just the door" do
    # A time-boxed admin who passed the admin gate and was then refused every
    # individual permission would be a half-open door: screens open, actions
    # inside them fail.
    it "a granted non-admin passes an arbitrary permission check" do
      grant_instance_admin(ordinary)

      expect(ordinary.has_permission?("ssp.write")).to be(true)
      expect(ordinary.has_permission?("catalogs.approve")).to be(true)
    end

    it "an ordinary user still fails those checks" do
      expect(ordinary.has_permission?("ssp.write")).to be(false)
    end
  end

  describe "IDENTITY stays with the break-glass account" do
    # This is the line that matters for separation of duties and for audit: a
    # temporary administrator must never be able to claim it WAS the break-glass
    # account.
    it "a granted non-admin is NOT admin?" do
      grant_instance_admin(ordinary)

      expect(ordinary.admin?).to be(false)
    end

    # DocumentApprovalService keys separation of duties on `admin?`, not on
    # authority — owner-decided 2026-08-21: "admin is global authority and has
    # absolute reign, break-glass type of use." A CdefDocument, because
    # APPROVE_PERMISSION only covers ControlCatalog, ProfileDocument and
    # CdefDocument.
    it "cannot approve a document it submitted, where the break-glass account can" do
      doc = create(:cdef_document)
      doc.update!(submitted_by_user_id: ordinary.id)
      grant_instance_admin(ordinary)

      expect(DocumentApprovalService.new(document: doc, actor: ordinary).can_approve?).to be(false),
             "a time-boxed administrator bypassed separation of duties"

      doc.update!(submitted_by_user_id: break_glass.id)
      expect(DocumentApprovalService.new(document: doc, actor: break_glass).can_approve?).to be(true),
             "the break-glass exemption is owner-decided and must survive"
    end
  end

  describe "revocation" do
    # What makes it time-boxed: the IdP drops the group, the next sign-in syncs,
    # and the authority is gone. EntitlementSync only ever revokes source: "idp".
    it "ends when the IdP-sourced grant is removed" do
      grant_instance_admin(ordinary)
      expect(ordinary.instance_administrator?).to be(true)

      ordinary.user_roles.where(source: "idp").destroy_all

      expect(ordinary.reload.instance_administrator?).to be(false)
    end
  end
end
