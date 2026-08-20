# frozen_string_literal: true

require "rails_helper"

# #1012 — organizations, their boundary assignments and their membership.
#
# Membership decides who can see what, so the assertions here are about the
# grant that results, and every guard is asserted in both directions.
RSpec.describe "Api::V1::Organizations", type: :request do
  let(:admin)     { create(:user, :admin) }
  let(:non_admin) { create(:user) }
  let(:member)    { create(:user) }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:valid_attributes) do
    { name: "Acme Agency #{SecureRandom.hex(4)}", description: "Test org",
      contact_person: "Dana Okafor", contact_email: "dana@example.gov" }
  end

  describe "POST /api/v1/organizations" do
    it "creates the organization, confirmed by an independent read" do
      expect {
        post api_v1_organizations_path, params: { organization: valid_attributes },
          headers: headers_for(admin), as: :json
      }.to change(Organization, :count).by(1)

      expect(response).to have_http_status(:created)
      id = response.parsed_body.dig("data", "id")

      get api_v1_organization_path(id), headers: headers_for(admin)
      expect(response.parsed_body.dig("data", "name")).to eq(valid_attributes[:name])
      expect(response.parsed_body.dig("data", "contact_email")).to eq("dana@example.gov")
    end

    it "refuses a non-admin, and creates nothing" do
      expect {
        post api_v1_organizations_path, params: { organization: valid_attributes },
          headers: headers_for(non_admin), as: :json
      }.not_to change(Organization, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an unauthenticated caller" do
      post api_v1_organizations_path, params: { organization: valid_attributes }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a field it does not accept" do
      post api_v1_organizations_path,
        params: { organization: valid_attributes.merge(status: "active") },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join(" ")).to include("status")
    end
  end

  describe "deactivate and reactivate" do
    let(:organization) { create(:organization) }

    it "deactivates and reactivates, never deleting the record" do
      headers = headers_for(admin)
      organization # built BEFORE the measurement: a lazy `let` first named
      # inside the block creates its record during the count.

      expect {
        post deactivate_api_v1_organization_path(organization), headers: headers, as: :json
      }.not_to change(Organization, :count)

      expect(response).to have_http_status(:ok)
      expect(organization.reload).not_to be_active

      post reactivate_api_v1_organization_path(organization), headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(organization.reload).to be_active
    end

    it "refuses a non-admin, and the organization stays active" do
      post deactivate_api_v1_organization_path(organization),
        headers: headers_for(non_admin), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(organization.reload).to be_active
    end
  end

  describe "POST /api/v1/organizations/:id/boundaries" do
    let(:organization) { create(:organization) }
    let(:boundary)     { create(:authorization_boundary, organization: nil) }

    it "assigns an unattached boundary" do
      post boundaries_api_v1_organization_path(organization),
        params: { authorization_boundary_id: boundary.id },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(boundary.reload.organization_id).to eq(organization.id)
      expect(response.parsed_body.dig("data", "moved")).to be(false)
    end

    it "reports a move when the boundary already belonged to another organization" do
      previous = create(:organization)
      boundary.update!(organization: previous)

      post boundaries_api_v1_organization_path(organization),
        params: { authorization_boundary_id: boundary.id },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "moved")).to be(true)
      expect(response.parsed_body.dig("data", "moved_from_organization_id")).to eq(previous.id)
      expect(boundary.reload.organization_id).to eq(organization.id)
    end

    it "refuses a non-admin, and the boundary is unmoved" do
      post boundaries_api_v1_organization_path(organization),
        params: { authorization_boundary_id: boundary.id },
        headers: headers_for(non_admin), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(boundary.reload.organization_id).to be_nil
    end

    it "404s for a boundary that does not exist" do
      post boundaries_api_v1_organization_path(organization),
        params: { authorization_boundary_id: 999_999 },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "membership" do
    let(:organization) { create(:organization) }

    it "adds a member with the requested role, and lists them" do
      post members_api_v1_organization_path(organization),
        params: { user_id: member.id, role: "org_admin" },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:created)
      membership_id = response.parsed_body.dig("data", "id")

      get members_api_v1_organization_path(organization), headers: headers_for(admin)

      rows = response.parsed_body["data"]
      expect(rows.map { |r| r["id"] }).to include(membership_id)
      expect(rows.find { |r| r["id"] == membership_id }["role"]).to eq("org_admin")
      expect(rows.find { |r| r["id"] == membership_id }["user_email"]).to eq(member.email)
    end

    it "refuses a role outside the configured set" do
      post members_api_v1_organization_path(organization),
        params: { user_id: member.id, role: "supreme_overlord" },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(organization.organization_memberships.count).to eq(0)
    end

    it "removes a member, and they stop appearing in the roster" do
      membership = organization.organization_memberships.create!(user: member, role: "org_admin")

      expect {
        delete remove_member_api_v1_organization_path(organization, membership_id: membership.id),
          headers: headers_for(admin)
      }.to change { organization.organization_memberships.count }.by(-1)

      expect(response).to have_http_status(:ok)

      get members_api_v1_organization_path(organization), headers: headers_for(admin)
      expect(response.parsed_body["data"].map { |r| r["id"] }).not_to include(membership.id)
    end

    it "refuses a non-admin adding a member, and adds nobody" do
      expect {
        post members_api_v1_organization_path(organization),
          params: { user_id: member.id, role: "org_admin" },
          headers: headers_for(non_admin), as: :json
      }.not_to change { organization.organization_memberships.count }

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a non-admin removing a member, and the member remains" do
      membership = organization.organization_memberships.create!(user: member, role: "org_admin")

      expect {
        delete remove_member_api_v1_organization_path(organization, membership_id: membership.id),
          headers: headers_for(non_admin)
      }.not_to change { organization.organization_memberships.count }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/organizations" do
    it "refuses a non-admin" do
      get api_v1_organizations_path, headers: headers_for(non_admin)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
