# frozen_string_literal: true

require "rails_helper"

# #1014 — RBAC roles through the API.
#
# Roles carry the permission sets every authorization check reads, so these
# specs care about what a role GRANTS after a write, not about the response
# echoing the request back.
RSpec.describe "Api::V1::Roles", type: :request do
  let(:admin)     { create(:user, :admin) }
  let(:non_admin) { create(:user) }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:valid_attributes) do
    { name: "custom_reviewer_#{SecureRandom.hex(4)}", display_name: "Custom Reviewer",
      scope: "authorization_boundary", description: "Reviews things", sort_order: 42 }
  end

  describe "POST /api/v1/roles" do
    it "creates the role and grants exactly the permissions requested" do
      expect {
        post api_v1_roles_path,
          params: { role: valid_attributes.merge(
            permissions: { "catalogs.read" => true, "catalogs.write" => false }
          ) },
          headers: headers_for(admin), as: :json
      }.to change(Role, :count).by(1)

      expect(response).to have_http_status(:created)

      role = Role.find(response.parsed_body.dig("data", "id"))
      expect(role.has_permission?("catalogs.read")).to be(true)
      expect(role.has_permission?("catalogs.write")).to be(false)

      # The response lists granted keys only, so a reader sees what the role
      # does rather than scanning every boolean.
      expect(response.parsed_body.dig("data", "permissions")).to include("catalogs.read")
      expect(response.parsed_body.dig("data", "permissions")).not_to include("catalogs.write")
    end

    it "accepts JSON booleans, not only the web form's \"1\"" do
      post api_v1_roles_path,
        params: { role: valid_attributes.merge(permissions: { "catalogs.read" => true }) },
        headers: headers_for(admin), as: :json

      role = Role.find(response.parsed_body.dig("data", "id"))
      expect(role.has_permission?("catalogs.read")).to be(true)
    end

    it "grants nothing a role was not given" do
      post api_v1_roles_path,
        params: { role: valid_attributes.merge(permissions: { "catalogs.read" => true }) },
        headers: headers_for(admin), as: :json

      role = Role.find(response.parsed_body.dig("data", "id"))
      granted = role.permissions.to_h.select { |_k, v| v }.keys
      expect(granted).to eq([ "catalogs.read" ])
    end

    it "cannot write a permission key the application does not enforce" do
      post api_v1_roles_path,
        params: { role: valid_attributes.merge(
          permissions: { "catalogs.read" => true, "invented.superpower" => true }
        ) },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:created)
      role = Role.find(response.parsed_body.dig("data", "id"))
      expect(role.permissions.keys).not_to include("invented.superpower")
    end

    it "refuses an invalid scope" do
      post api_v1_roles_path,
        params: { role: valid_attributes.merge(scope: "galaxy") },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a duplicate name" do
      existing = create(:role)

      post api_v1_roles_path,
        params: { role: valid_attributes.merge(name: existing.name) },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a non-admin, and creates nothing" do
      expect {
        post api_v1_roles_path, params: { role: valid_attributes },
          headers: headers_for(non_admin), as: :json
      }.not_to change(Role, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an unauthenticated caller" do
      post api_v1_roles_path, params: { role: valid_attributes }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a field it does not accept" do
      post api_v1_roles_path,
        params: { role: valid_attributes.merge(id: 999_999) },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join(" ")).to include("id")
    end
  end

  describe "PATCH /api/v1/roles/:id" do
    let(:role) { create(:role, :authorization_boundary_scoped) }

    it "replaces the permission set wholesale, so an omitted key is revoked" do
      role.assign_permissions("catalogs.read" => true, "catalogs.write" => true)
      role.save!

      patch api_v1_role_path(role),
        params: { role: { permissions: { "catalogs.read" => true } } },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(role.reload.has_permission?("catalogs.read")).to be(true)
      expect(role.has_permission?("catalogs.write")).to be(false)
    end

    it "leaves permissions untouched when the request does not mention them" do
      role.assign_permissions("catalogs.write" => true)
      role.save!

      patch api_v1_role_path(role),
        params: { role: { display_name: "Renamed" } },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(role.reload.display_name).to eq("Renamed")
      expect(role.has_permission?("catalogs.write")).to be(true)
    end

    it "refuses a non-admin, and the role is unchanged" do
      original = role.display_name

      patch api_v1_role_path(role), params: { role: { display_name: "Hijacked" } },
        headers: headers_for(non_admin), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(role.reload.display_name).to eq(original)
    end
  end

  describe "GET /api/v1/roles" do
    it "filters by scope truthfully" do
      instance_role = create(:role, scope: "instance")
      boundary_role = create(:role, :authorization_boundary_scoped)

      get api_v1_roles_path, params: { scope: "instance" }, headers: headers_for(admin)

      ids = response.parsed_body["data"].map { |r| r["id"] }
      expect(ids).to include(instance_role.id)
      expect(ids).not_to include(boundary_role.id)
    end

    it "refuses a non-admin" do
      get api_v1_roles_path, headers: headers_for(non_admin)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/roles/:id" do
    it "deletes an unassigned role" do
      role = create(:role, :authorization_boundary_scoped)

      expect {
        delete api_v1_role_path(role), headers: headers_for(admin)
      }.to change(Role, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it "refuses to delete a role that is still assigned, and keeps it" do
      role = create(:role, :authorization_boundary_scoped)
      boundary = create(:authorization_boundary)
      create(:user_role, user: create(:user), role: role, authorization_boundary: boundary)

      expect {
        delete api_v1_role_path(role), headers: headers_for(admin)
      }.not_to change(Role, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/assigned to users/i)
    end

    it "refuses a non-admin, and the role survives" do
      role = create(:role, :authorization_boundary_scoped)

      expect {
        delete api_v1_role_path(role), headers: headers_for(non_admin)
      }.not_to change(Role, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
