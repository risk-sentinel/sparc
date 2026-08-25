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

  # #875 — this used to stub SparcConfig.auth_boundary_roles to the model's own
  # defaults, because the committed .env holds human LABELS that the role enum
  # rejected. That stub is why the suite never caught the 500 it was working
  # around. The enum is gone and labels now resolve, so the variable is simply
  # cleared: these examples are about #869 and should not inherit whatever role
  # list this machine happens to configure. dotenv loads in test, so leaving it
  # ambient would make them machine-dependent.
  around do |example|
    original = ENV["SPARC_AUTH_BOUNDARY_ROLES"]
    ENV.delete("SPARC_AUTH_BOUNDARY_ROLES")
    example.run
  ensure
    original.nil? ? ENV.delete("SPARC_AUTH_BOUNDARY_ROLES") : ENV["SPARC_AUTH_BOUNDARY_ROLES"] = original
  end

  before { sign_in_as(user) }

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

      expect(response).to have_http_status(:unprocessable_content)
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

  # #875 — Add Member end-to-end against a CONFIGURED role list, both
  # directions: a configured role saves and renders, an unconfigured one is
  # refused. The bug was that the controller's allowlist and the model's enum
  # disagreed about what was acceptable, so a configured label passed the first
  # and raised ArgumentError inside the second — a 500 on submit.
  describe "a configured role vocabulary (#875)" do
    def configure_roles(value)
      ENV["SPARC_AUTH_BOUNDARY_ROLES"] = value
    end

    it "renders the configured roles in the dropdown, not the defaults" do
      configure_roles("isso,Security Champion")

      get new_authorization_boundary_membership_path(boundary)

      doc = Nokogiri::HTML(response.body)
      values = doc.css("select[name='authorization_boundary_membership[role]'] option").map { |o| o["value"] }
      expect(values).to contain_exactly("isso", "security_champion")
      expect(values).not_to include("ciso")
    end

    it "accepts a custom configured role and shows its label" do
      configure_roles("isso,Security Champion")

      expect {
        post authorization_boundary_memberships_path(boundary),
             params: { authorization_boundary_membership: {
               user_name: "Dana Reed", user_email: "dana@example.gov", role: "security_champion"
             } }
      }.to change { boundary.authorization_boundary_memberships.count }.by(1)

      expect(response).to redirect_to(new_authorization_boundary_membership_path(boundary))
      expect(flash[:success]).to include("Security Champion")
      expect(boundary.authorization_boundary_memberships.last.role).to eq("security_champion")
    end

    it "refuses a role outside the configured list without a 500" do
      configure_roles("isso")

      expect {
        post authorization_boundary_memberships_path(boundary),
             params: { authorization_boundary_membership: {
               user_name: "Dana Reed", user_email: "dana@example.gov", role: "Security Champion"
             } }
      }.not_to change { boundary.authorization_boundary_memberships.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Current Personnel Roster")
      expect(flash.now[:error]).to include("is not an available role")
    end

    # The exact configuration our own .env.example shipped, which produced the
    # ArgumentError this issue reports. Every entry is a human label.
    it "accepts the label form the shipped .env.example used" do
      configure_roles("Assessor / 3PAO, Authorizing Official (AO), CISO, ISSO, Team Member, System Owner (SO), View Only")

      get new_authorization_boundary_membership_path(boundary)
      expect(response).to have_http_status(:ok)

      expect {
        post authorization_boundary_memberships_path(boundary),
             params: { authorization_boundary_membership: {
               user_name: "Dana Reed", user_email: "dana@example.gov", role: "system_owner"
             } }
      }.to change { boundary.authorization_boundary_memberships.count }.by(1)

      expect(response).to redirect_to(new_authorization_boundary_membership_path(boundary))
      expect(boundary.authorization_boundary_memberships.last.role).to eq("system_owner")
    end

    it "renders proper labels rather than titleized ones" do
      configure_roles("Assessor / 3PAO, Authorizing Official (AO)")

      get new_authorization_boundary_membership_path(boundary)

      expect(response.body).to include("Assessor / 3PAO")
      expect(response.body).to include("Authorizing Official (AO)")
      expect(response.body).not_to include("Assessor / 3 Pao")
      expect(response.body).not_to include("Authorizing Official (Ao)")
    end
  end
end
