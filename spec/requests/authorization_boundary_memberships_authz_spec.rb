# frozen_string_literal: true

require "rails_helper"

# CRITICAL regression — the web roster had no authorization at all.
#
# `AuthorizationBoundaryMembershipsController` guarded only `set_*` callbacks,
# and `set_authorization_boundary` is an unscoped `find_by!(slug:)`.
# ApplicationController enforces AUTHENTICATION only. So any signed-in user
# could add, re-role or remove members on any boundary whose slug they knew.
#
# Demonstrated before the fix: a non-admin, non-member POST returned 302 with
# "Member 'Victim' added as Assessor / 3PAO." Boundary roles gate access to
# compliance documents, so that is privilege escalation, not a tidy-up.
#
# The Api::V1 equivalent was already gated; only the web path was open. These
# examples pin both directions so the two surfaces cannot drift apart again.
RSpec.describe "Authorization boundary membership authorization", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:target)   { create(:user, email: "target@example.com") }
  let(:role)     { AuthorizationBoundaryMembership.available_roles.first }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def membership_params
    { authorization_boundary_membership: {
      user_name: "Target", user_email: target.email,
      role: role.is_a?(Hash) ? role[:value] : role
    } }
  end

  describe "a signed-in user with no relationship to the boundary" do
    before { sign_in_as(create(:user)) }

    it "cannot add a member" do
      expect {
        post authorization_boundary_memberships_path(boundary), params: membership_params
      }.not_to change(AuthorizationBoundaryMembership, :count)
    end

    # Refused and sent away, not quietly dropped — the user is told, and the
    # record is definitively absent.
    it "is refused rather than silently no-oped" do
      post authorization_boundary_memberships_path(boundary), params: membership_params

      expect(response).to redirect_to(root_path)
      expect(AuthorizationBoundaryMembership.exists?(user_email: target.email)).to be(false)
    end

    it "cannot reach the new-member form" do
      get new_authorization_boundary_membership_path(boundary)

      expect(response).to redirect_to(root_path)
    end

    it "cannot remove an existing member" do
      membership = create(:authorization_boundary_membership,
                          authorization_boundary: boundary, user_email: target.email)

      expect {
        delete authorization_boundary_membership_path(boundary, membership)
      }.not_to change(AuthorizationBoundaryMembership, :count)
    end

    # The denial is auditable — a refused privilege change is exactly the event
    # an assessor needs to see.
    it "records an authorization_failure" do
      expect {
        post authorization_boundary_memberships_path(boundary), params: membership_params
      }.to change { AuditEvent.where(action: "authorization_failure").count }.by_at_least(1)
    end
  end

  describe "an instance admin" do
    before { sign_in_as(create(:user, :admin)) }

    it "can still manage the roster" do
      expect {
        post authorization_boundary_memberships_path(boundary), params: membership_params
      }.to change(AuthorizationBoundaryMembership, :count).by(1)
    end
  end
end
