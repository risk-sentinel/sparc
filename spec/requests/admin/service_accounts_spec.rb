# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ServiceAccounts", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:owner) { create(:user) }

  before { sign_in_as(admin) }

  describe "GET /admin/service_accounts" do
    it "lists service accounts" do
      sa = create(:user, service_account: true, owner: owner, display_name: "pipeline-sa")
      get admin_service_accounts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("pipeline-sa")
    end

    it "requires admin" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      sign_in_as(create(:user))
      get admin_service_accounts_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/service_accounts/new" do
    it "renders the form" do
      get new_admin_service_account_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Service Account")
    end
  end

  describe "POST /admin/service_accounts" do
    it "creates a service account with initial token" do
      expect {
        post admin_service_accounts_path, params: {
          user: { email: "ci@service.local", display_name: "CI Pipeline", owner_id: owner.id },
          expires_in_days: "90",
          allowed_endpoints: "/api/v1/ssp_documents\n/api/v1/sar_documents",
          allowed_cidrs: "10.0.0.0/8"
        }
      }.to change(User.service_accounts, :count).by(1)
       .and change(ApiToken, :count).by(1)

      sa = User.service_accounts.last
      expect(sa.service_account?).to be true
      expect(sa.owner).to eq(owner)

      token = sa.api_tokens.first
      expect(token.allowed_endpoints).to eq([ "/api/v1/ssp_documents", "/api/v1/sar_documents" ])
      expect(token.allowed_cidrs).to eq([ "10.0.0.0/8" ])
      expect(flash[:api_token]).to start_with("sparc_sa_")
    end

    it "rejects service account with admin flag" do
      sa = build(:user, service_account: true, admin: true, owner: owner)
      expect(sa).not_to be_valid
      expect(sa.errors[:admin]).to include("cannot be true for service accounts")
    end
  end

  describe "GET /admin/service_accounts/:id" do
    it "shows service account details" do
      sa = create(:user, service_account: true, owner: owner, display_name: "test-sa")
      get admin_service_account_path(sa)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("test-sa")
    end
  end

  describe "PATCH /admin/service_accounts/:id/disable" do
    it "disables the service account" do
      sa = create(:user, service_account: true, owner: owner)
      patch disable_admin_service_account_path(sa), params: { reason: "security_review" }
      sa.reload
      expect(sa.disabled?).to be true
      expect(sa.disabled_reason).to eq("security_review")
      expect(sa.status).to eq("suspended")
    end
  end

  describe "PATCH /admin/service_accounts/:id/enable" do
    it "re-enables a disabled service account" do
      sa = create(:user, service_account: true, owner: owner, disabled_at: Time.current, disabled_reason: "test", status: "suspended")
      patch enable_admin_service_account_path(sa)
      sa.reload
      expect(sa.disabled?).to be false
      expect(sa.status).to eq("active")
    end
  end

  describe "POST /admin/service_accounts/:id/regenerate_token" do
    it "revokes old tokens and generates new one" do
      sa = create(:user, service_account: true, owner: owner)
      old_token = ApiToken.generate!(user: sa, name: "old")

      post regenerate_token_admin_service_account_path(sa), params: { expires_in_days: "60" }

      expect(sa.api_tokens.reload.count).to eq(1)
      expect(sa.api_tokens.first.name).to eq("Regenerated token")
      expect(flash[:api_token]).to start_with("sparc_sa_")
    end
  end

  describe "DELETE /admin/service_accounts/:id" do
    it "deactivates the service account" do
      sa = create(:user, service_account: true, owner: owner)
      delete admin_service_account_path(sa)
      sa.reload
      expect(sa.status).to eq("deactivated")
    end
  end
end
