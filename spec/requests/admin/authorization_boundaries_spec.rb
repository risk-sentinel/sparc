# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AuthorizationBoundaries", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  describe "authorization" do
    it "redirects non-admin users" do
      sign_in_as(regular_user)
      get admin_authorization_boundaries_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/authorization_boundaries" do
    before { sign_in_as(admin) }

    it "lists all authorization boundaries" do
      authorization_boundary = create(:authorization_boundary, name: "Test ATO Authorization Boundary")
      get admin_authorization_boundaries_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test ATO Authorization Boundary")
    end
  end

  describe "GET /admin/authorization_boundaries/:id" do
    before { sign_in_as(admin) }

    it "shows authorization boundary with members and legacy memberships" do
      authorization_boundary = create(:authorization_boundary, :with_members, name: "Alpha System")
      get admin_authorization_boundary_path(authorization_boundary)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alpha System")
      expect(response.body).to include("Legacy Memberships")
    end
  end

  describe "POST /admin/authorization_boundaries/:id/add_member" do
    before { sign_in_as(admin) }

    let(:authorization_boundary) { create(:authorization_boundary) }
    let(:user) { create(:user) }
    let(:role) { create(:role, :authorization_boundary_scoped) }

    it "assigns a user to an authorization boundary role" do
      expect {
        post add_member_admin_authorization_boundary_path(authorization_boundary), params: {
          user_id: user.id, role_id: role.id
        }
      }.to change(UserRole, :count).by(1)

      expect(response).to redirect_to(admin_authorization_boundary_path(authorization_boundary))
      ur = UserRole.last
      expect(ur.user).to eq(user)
      expect(ur.role).to eq(role)
      expect(ur.authorization_boundary).to eq(authorization_boundary)
    end

    it "creates an audit event" do
      expect {
        post add_member_admin_authorization_boundary_path(authorization_boundary), params: {
          user_id: user.id, role_id: role.id
        }
      }.to change(AuditEvent.where(action: "authorization_boundary_member_added"), :count).by(1)
    end

    it "rejects duplicate assignment" do
      create(:user_role, user: user, role: role, authorization_boundary: authorization_boundary)
      post add_member_admin_authorization_boundary_path(authorization_boundary), params: {
        user_id: user.id, role_id: role.id
      }
      expect(response).to redirect_to(admin_authorization_boundary_path(authorization_boundary))
      expect(flash[:error]).to be_present
    end
  end

  describe "DELETE /admin/authorization_boundaries/:id/remove_member" do
    before { sign_in_as(admin) }

    let(:authorization_boundary) { create(:authorization_boundary) }
    let(:role) { create(:role, :authorization_boundary_scoped) }
    let(:user) { create(:user) }

    it "removes a user from an authorization boundary role" do
      ur = create(:user_role, user: user, role: role, authorization_boundary: authorization_boundary)
      expect {
        delete remove_member_admin_authorization_boundary_path(authorization_boundary, user_role_id: ur.id)
      }.to change(UserRole, :count).by(-1)

      expect(response).to redirect_to(admin_authorization_boundary_path(authorization_boundary))
    end

    it "creates an audit event" do
      ur = create(:user_role, user: user, role: role, authorization_boundary: authorization_boundary)
      expect {
        delete remove_member_admin_authorization_boundary_path(authorization_boundary, user_role_id: ur.id)
      }.to change(AuditEvent.where(action: "authorization_boundary_member_removed"), :count).by(1)
    end
  end
end
