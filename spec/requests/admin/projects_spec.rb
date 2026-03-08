# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Projects", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  describe "authorization" do
    it "redirects non-admin users" do
      sign_in_as(regular_user)
      get admin_projects_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/projects" do
    before { sign_in_as(admin) }

    it "lists all projects" do
      project = create(:project, name: "Test ATO Project")
      get admin_projects_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test ATO Project")
    end
  end

  describe "GET /admin/projects/:id" do
    before { sign_in_as(admin) }

    it "shows project with members and legacy memberships" do
      project = create(:project, :with_members, name: "Alpha System")
      get admin_project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alpha System")
      expect(response.body).to include("Legacy Memberships")
    end
  end

  describe "POST /admin/projects/:id/add_member" do
    before { sign_in_as(admin) }

    let(:project) { create(:project) }
    let(:user) { create(:user) }
    let(:role) { create(:role, :project_scoped) }

    it "assigns a user to a project role" do
      expect {
        post add_member_admin_project_path(project), params: {
          user_id: user.id, role_id: role.id
        }
      }.to change(UserRole, :count).by(1)

      expect(response).to redirect_to(admin_project_path(project))
      ur = UserRole.last
      expect(ur.user).to eq(user)
      expect(ur.role).to eq(role)
      expect(ur.project).to eq(project)
    end

    it "creates an audit event" do
      expect {
        post add_member_admin_project_path(project), params: {
          user_id: user.id, role_id: role.id
        }
      }.to change(AuditEvent.where(action: "project_member_added"), :count).by(1)
    end

    it "rejects duplicate assignment" do
      create(:user_role, user: user, role: role, project: project)
      post add_member_admin_project_path(project), params: {
        user_id: user.id, role_id: role.id
      }
      expect(response).to redirect_to(admin_project_path(project))
      expect(flash[:error]).to be_present
    end
  end

  describe "DELETE /admin/projects/:id/remove_member" do
    before { sign_in_as(admin) }

    let(:project) { create(:project) }
    let(:role) { create(:role, :project_scoped) }
    let(:user) { create(:user) }

    it "removes a user from a project role" do
      ur = create(:user_role, user: user, role: role, project: project)
      expect {
        delete remove_member_admin_project_path(project, user_role_id: ur.id)
      }.to change(UserRole, :count).by(-1)

      expect(response).to redirect_to(admin_project_path(project))
    end

    it "creates an audit event" do
      ur = create(:user_role, user: user, role: role, project: project)
      expect {
        delete remove_member_admin_project_path(project, user_role_id: ur.id)
      }.to change(AuditEvent.where(action: "project_member_removed"), :count).by(1)
    end
  end
end
