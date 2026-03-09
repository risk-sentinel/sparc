# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audit logging integration", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  describe "project CRUD" do
    it "logs project_created on create" do
      expect {
        post projects_path, params: { project: { name: "Audit Test", status: "active" } }
      }.to change(AuditEvent.where(action: "project_created"), :count).by(1)

      event = AuditEvent.where(action: "project_created").last
      expect(event.subject_type).to eq("Project")
      expect(event.user).to eq(user)
      expect(event.metadata["name"]).to eq("Audit Test")
    end

    it "logs project_updated on update" do
      project = create(:project, name: "Original")
      expect {
        patch project_path(project), params: { project: { name: "Updated" } }
      }.to change(AuditEvent.where(action: "project_updated"), :count).by(1)
    end

    it "logs project_deleted on destroy" do
      project = create(:project, name: "To Delete")
      expect {
        delete project_path(project)
      }.to change(AuditEvent.where(action: "project_deleted"), :count).by(1)

      event = AuditEvent.where(action: "project_deleted").last
      expect(event.metadata["name"]).to eq("To Delete")
    end
  end

  describe "authorization failure logging" do
    it "logs authorization_failure when non-admin accesses admin path" do
      regular = create(:user)
      sign_in_as(regular)

      expect {
        get admin_users_path
      }.to change(AuditEvent.where(action: "authorization_failure"), :count).by(1)

      event = AuditEvent.where(action: "authorization_failure").last
      expect(event.metadata["reason"]).to include("Admin access required")
      expect(event.metadata["path"]).to include("/admin/users")
    end
  end

  describe "evidence CRUD" do
    it "logs evidence_created on create" do
      expect {
        post evidences_path, params: {
          evidence: { title: "Test Evidence", description: "Test", evidence_type: "test_result" }
        }
      }.to change(AuditEvent.where(action: "evidence_created"), :count).by(1)
    end
  end
end
