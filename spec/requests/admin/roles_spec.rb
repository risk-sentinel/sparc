# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Roles", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  describe "authorization" do
    it "redirects non-admin users" do
      sign_in_as(regular_user)
      get admin_roles_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/roles" do
    before { sign_in_as(admin) }

    it "lists all roles" do
      role = create(:role, display_name: "Test Role")
      get admin_roles_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test Role")
    end
  end

  describe "GET /admin/roles/:id" do
    before { sign_in_as(admin) }

    it "shows role details and permissions" do
      role = create(:role, display_name: "ISSO", permissions: { "ssp.read" => true, "ssp.write" => false })
      get admin_role_path(role)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ISSO")
    end
  end

  describe "GET /admin/roles/new" do
    before { sign_in_as(admin) }

    it "renders the new role form" do
      get new_admin_role_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Role")
    end
  end

  describe "POST /admin/roles" do
    before { sign_in_as(admin) }

    it "creates a role with permissions" do
      expect {
        post admin_roles_path, params: {
          role: {
            name: "test_role",
            display_name: "Test Role",
            scope: "project",
            sort_order: 99,
            description: "A test role",
            permissions: { "ssp.read" => "1", "ssp.write" => "1" }
          }
        }
      }.to change(Role, :count).by(1)

      role = Role.find_by(name: "test_role")
      expect(role.has_permission?("ssp.read")).to be true
      expect(role.has_permission?("ssp.write")).to be true
      expect(role.has_permission?("sar.read")).to be false
    end

    it "creates an audit event" do
      expect {
        post admin_roles_path, params: {
          role: { name: "audit_test", display_name: "Audit Test", scope: "instance" }
        }
      }.to change(AuditEvent.where(action: "role_created"), :count).by(1)
    end

    it "re-renders form on invalid input" do
      post admin_roles_path, params: {
        role: { name: "", display_name: "", scope: "invalid" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /admin/roles/:id" do
    before { sign_in_as(admin) }

    let(:role) { create(:role, display_name: "Original") }

    it "updates the role" do
      patch admin_role_path(role), params: {
        role: { display_name: "Updated Name" }
      }
      expect(response).to redirect_to(admin_role_path(role))
      expect(role.reload.display_name).to eq("Updated Name")
    end

    it "updates permissions" do
      patch admin_role_path(role), params: {
        role: {
          display_name: role.display_name,
          permissions: { "catalogs.read" => "1", "catalogs.write" => "1" }
        }
      }
      role.reload
      expect(role.has_permission?("catalogs.read")).to be true
      expect(role.has_permission?("catalogs.write")).to be true
    end

    it "creates an audit event" do
      expect {
        patch admin_role_path(role), params: {
          role: { display_name: "Changed" }
        }
      }.to change(AuditEvent.where(action: "role_updated"), :count).by(1)
    end
  end

  describe "DELETE /admin/roles/:id" do
    before { sign_in_as(admin) }

    it "deletes an unassigned role" do
      role = create(:role)
      expect {
        delete admin_role_path(role)
      }.to change(Role, :count).by(-1)
      expect(response).to redirect_to(admin_roles_path)
    end

    it "refuses to delete a role with active assignments" do
      role = create(:role)
      create(:user_role, role: role)
      expect {
        delete admin_role_path(role)
      }.not_to change(Role, :count)
      expect(response).to redirect_to(admin_role_path(role))
    end

    it "creates an audit event" do
      role = create(:role)
      expect {
        delete admin_role_path(role)
      }.to change(AuditEvent.where(action: "role_deleted"), :count).by(1)
    end
  end
end
