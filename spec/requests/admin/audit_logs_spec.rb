# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AuditLogs", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  describe "authorization" do
    it "redirects non-admin users" do
      sign_in_as(regular_user)
      get admin_audit_logs_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/audit_logs" do
    before { sign_in_as(admin) }

    it "lists audit events" do
      AuditEvent.log(user: admin, action: "login_success", ip_address: "127.0.0.1")
      get admin_audit_logs_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Login success")
    end

    it "filters by user_id" do
      AuditEvent.log(user: admin, action: "login_success", ip_address: "127.0.0.1")
      AuditEvent.log(user: regular_user, action: "login_success", ip_address: "10.0.0.1")

      get admin_audit_logs_path, params: { user_id: admin.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin.email)
    end

    it "filters by category" do
      AuditEvent.log(user: admin, action: "login_success", ip_address: "127.0.0.1")
      AuditEvent.log(user: admin, action: "ssp_document_created", ip_address: "127.0.0.1",
                     subject: SspDocument.create!(name: "test", status: "pending"))

      get admin_audit_logs_path, params: { category: "Authentication" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Login success")
    end

    it "filters by date range" do
      AuditEvent.log(user: admin, action: "login_success", ip_address: "127.0.0.1")
      get admin_audit_logs_path, params: { start_date: Date.today.to_s, end_date: Date.today.to_s }
      expect(response).to have_http_status(:ok)
    end

    it "searches by text query" do
      AuditEvent.log(user: admin, action: "login_success", ip_address: "127.0.0.1")
      get admin_audit_logs_path, params: { q: "login" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Login success")
    end

    it "exports CSV" do
      AuditEvent.log(user: admin, action: "login_success", ip_address: "127.0.0.1")
      get admin_audit_logs_path(format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("timestamp")
      expect(response.body).to include("login_success")
    end
  end

  describe "GET /admin/audit_logs/:id" do
    before { sign_in_as(admin) }

    it "shows event detail" do
      event = AuditEvent.log(user: admin, action: "login_success", ip_address: "127.0.0.1",
                             metadata: { provider: "local" })
      get admin_audit_log_path(event)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Audit Event")
      expect(response.body).to include("Login success")
    end

    it "shows subject details when present" do
      project = create(:project, name: "Test Project")
      event = AuditEvent.log(user: admin, action: "project_created", ip_address: "127.0.0.1",
                             subject: project, metadata: { name: "Test Project" })
      get admin_audit_log_path(event)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Subject")
      expect(response.body).to include("Project")
    end
  end
end
