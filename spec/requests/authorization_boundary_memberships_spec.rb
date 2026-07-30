# frozen_string_literal: true

require "rails_helper"

# #869 — building a Personnel Roster is inherently repetitive, but every
# successful create bounced the operator back to the boundary screen. Adding a
# second person meant re-opening Add Member and starting over, with no view of
# who was already assigned.
#
# These specs pin the loop: stay on the add screen, see the roster as it grows,
# and leave only when you say so.
RSpec.describe "Authorization boundary memberships (#869)", type: :request do
  let(:user) { create(:user, admin: true) }
  let(:boundary) { create(:authorization_boundary) }

  before do
    sign_in_as(user)
    # The committed .env sets SPARC_AUTH_BOUNDARY_ROLES to human LABELS, which
    # the role enum rejects — see #875. Stub the configured roles to the model's
    # own defaults so these specs exercise #869 rather than that misconfiguration,
    # and so they behave the same locally and in CI.
    allow(SparcConfig).to receive(:auth_boundary_roles)
      .and_return(AuthorizationBoundaryMembership::DEFAULT_ROLES)
  end

  def member_params(name: "Dana Reed", role: "system_owner")
    { authorization_boundary_membership: { user_name: name, user_email: "dana@example.gov", role: role } }
  end

  describe "staying in the add loop" do
    it "returns to the add form after a successful create, not the boundary" do
      post authorization_boundary_memberships_path(boundary), params: member_params

      expect(response).to redirect_to(new_authorization_boundary_membership_path(boundary))
      expect(response).not_to redirect_to(authorization_boundary_path(boundary))
    end

    it "confirms which member was added" do
      post authorization_boundary_memberships_path(boundary), params: member_params

      expect(flash[:success]).to include("Dana Reed")
    end

    it "still creates the member and audits it" do
      expect { post authorization_boundary_memberships_path(boundary), params: member_params }
        .to change { boundary.authorization_boundary_memberships.count }.by(1)

      expect(AuditEvent.where(action: "authorization_boundary_membership_created")).to exist
    end

    it "presents a blank form ready for the next entry" do
      post authorization_boundary_memberships_path(boundary), params: member_params
      follow_redirect!

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("input[name='authorization_boundary_membership[user_name]']")["value"]).to be_blank
      expect(doc.at_css("input[name='authorization_boundary_membership[user_name]'][autofocus]")).to be_present
    end
  end

  describe "seeing the roster while building it" do
    it "shows existing members on the add screen" do
      create(:authorization_boundary_membership, authorization_boundary: boundary,
             user_name: "Existing Person", user_email: "existing@example.gov")

      get new_authorization_boundary_membership_path(boundary)

      expect(response.body).to include("Current Personnel Roster")
      expect(response.body).to include("Existing Person")
    end

    it "includes the member just added, so progress is visible" do
      post authorization_boundary_memberships_path(boundary), params: member_params
      follow_redirect!

      expect(response.body).to include("Dana Reed")
    end

    it "shows admin-assigned personnel too, not only legacy memberships" do
      # #770 bug 3 — the roster is unified; the add screen must not present a
      # narrower view than the boundary screen, or it would invite duplicates.
      allow_any_instance_of(AuthorizationBoundary).to receive(:personnel_roster).and_return([
        instance_double("PersonnelEntry", name: "Admin Assigned", email: "aa@example.gov",
                        role_label: "System Owner", source: :assigned, membership: nil)
      ])

      get new_authorization_boundary_membership_path(boundary)

      expect(response.body).to include("Admin Assigned")
      expect(response.body).to include("Admin")
    end

    it "does not offer per-row Remove on the add screen" do
      create(:authorization_boundary_membership, authorization_boundary: boundary, user_name: "Existing Person")

      get new_authorization_boundary_membership_path(boundary)

      expect(response.body).not_to include("Remove this member?")
    end

    it "says so plainly when the roster is empty" do
      get new_authorization_boundary_membership_path(boundary)

      expect(response.body).to include("No members assigned")
    end
  end

  describe "leaving is intentional" do
    it "offers an explicit way back to the boundary" do
      get new_authorization_boundary_membership_path(boundary)

      expect(response.body).to include(authorization_boundary_path(boundary))
      expect(response.body).to match(/Done|Cancel/)
    end

    it "editing a member still returns to the boundary — a correction is not a loop" do
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary)

      patch authorization_boundary_membership_path(boundary, membership),
            params: { authorization_boundary_membership: { user_name: "Renamed" } }

      expect(response).to redirect_to(authorization_boundary_path(boundary))
    end
  end

  describe "validation failure" do
    it "re-renders the form and still shows the roster" do
      create(:authorization_boundary_membership, authorization_boundary: boundary, user_name: "Existing Person")

      expect {
        post authorization_boundary_memberships_path(boundary),
             params: { authorization_boundary_membership: { user_name: "", user_email: "x@example.gov" } }
      }.not_to change { boundary.authorization_boundary_memberships.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Current Personnel Roster")
      expect(response.body).to include("Existing Person")
    end
  end

  describe "the boundary screen keeps its management controls" do
    it "still offers Edit and Remove there" do
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary)

      get authorization_boundary_path(boundary)

      expect(response.body).to include(edit_authorization_boundary_membership_path(boundary, membership))
      expect(response.body).to include("Remove this member?")
    end
  end
end
