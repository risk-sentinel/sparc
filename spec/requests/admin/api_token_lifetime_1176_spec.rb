# frozen_string_literal: true

require "rails_helper"

# #1176 — the admin screens: the endpoint picker, required expiry for service
# accounts, renew / reissue, and a Regenerate that no longer widens a token.
RSpec.describe "Admin API token lifetime and limits (#1176)", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:owner) { create(:user) }

  before { sign_in_as(admin) }

  def create_account(**extra)
    post admin_service_accounts_path, params: {
      user: { display_name: "bot", email: "team@example.com", owner_id: owner.id },
      expires_in_days: "90", endpoint_picker: "1"
    }.merge(extra)
  end

  describe "creating a service account" do
    it "stores the per-resource entries the picker sends" do
      create_account(allowed_endpoints: [ "", "ssp_documents:read", "evidences:write" ])

      token = User.service_accounts.last.api_tokens.sole
      expect(token.allowed_endpoints).to eq([ "ssp_documents:read", "evidences:write" ])
    end

    it "stores All endpoints as unrestricted" do
      create_account(allowed_endpoints: [ "", "*" ])

      expect(User.service_accounts.last.api_tokens.sole.allowed_endpoints).to eq([])
    end

    it "refuses a submission with nothing ticked, creating nothing" do
      expect { create_account(allowed_endpoints: [ "" ]) }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose the endpoints this token may reach, or All endpoints")
      # Re-shown as submitted: the refusal is not quietly turned into All.
      expect(response.body[/<input[^>]*id="sa_endpoints_all"[^>]*>/]).not_to include("checked")
    end

    it "starts a fresh form on All endpoints" do
      get new_admin_service_account_path

      expect(response.body[/<input[^>]*id="sa_endpoints_all"[^>]*>/]).to include("checked")
      expect(response.body[/<input[^>]*id="sa_endpoints_ssp_documents_read"[^>]*>/]).not_to include("checked")
    end

    it "refuses a lifetime past the cap, creating nothing" do
      allow(SparcConfig).to receive(:api_token_max_days).and_return(30)

      expect { create_account(expires_in_days: "90", allowed_endpoints: [ "*" ]) }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      # The FORM comes back with the reason beside the account's own errors,
      # not a bare error page (Rails' 422 for an unrescued RecordInvalid).
      expect(response.body).to include('name="user[display_name]"')
      expect(response.body).to include("Token: Expires at may be at most 30 days")
    end

    it "lets one team mailbox own two accounts" do
      2.times { create_account(allowed_endpoints: [ "*" ]) }

      expect(User.service_accounts.where(email: "team@example.com").count).to eq(2)
    end

    it "offers no Never and nothing past the cap" do
      allow(SparcConfig).to receive(:api_token_max_days).and_return(60)

      get new_admin_service_account_path

      expect(response.body).to include("All endpoints")
      expect(response.body).to include('value="ssp_documents:read"')
      select = response.body[/<select[^>]*name="expires_in_days".*?<\/select>/m]
      expect(select).not_to include(">Never<")
      expect(select).not_to include('value="90"')
      expect(select).to include('value="60"')
    end
  end

  describe "Regenerate" do
    it "keeps the newest token's limits instead of issuing an unrestricted token" do
      sa = create(:user, :service_account, owner: owner)
      ApiToken.generate!(user: sa, name: "t", expires_at: 30.days.from_now,
                         allowed_endpoints: [ "ssp_documents:read" ], allowed_cidrs: [ "10.0.0.0/8" ])

      post regenerate_token_admin_service_account_path(sa)

      token = sa.api_tokens.reload.sole
      expect(token.allowed_endpoints).to eq([ "ssp_documents:read" ])
      expect(token.allowed_cidrs).to eq([ "10.0.0.0/8" ])
      expect(flash[:api_token]).to start_with("sparc_sa_")
    end
  end

  describe "renew and reissue from the pages" do
    let(:sa) { create(:user, :service_account, owner: owner) }
    let!(:token) do
      ApiToken.generate!(user: sa, name: "pipeline", expires_at: 30.days.from_now,
                         allowed_endpoints: [ "evidences:write" ])
    end

    it "renews and returns to the account page with the new token shown once" do
      expect { post renew_admin_user_api_token_path(sa, token) }.to change { sa.api_tokens.count }.by(1)

      expect(response).to redirect_to(admin_service_account_path(sa))
      expect(flash[:api_token]).to start_with("sparc_sa_")
      expect(sa.api_tokens.order(:created_at).last.allowed_endpoints).to eq([ "evidences:write" ])
      expect(token.reload.expires_at).to be <= (SparcConfig.api_token_renewal_grace_days.days + 1.minute).from_now
    end

    it "reissues: the old token is gone" do
      post reissue_admin_user_api_token_path(sa, token)

      expect(ApiToken.exists?(token.id)).to be false
      expect(sa.api_tokens.sole.allowed_endpoints).to eq([ "evidences:write" ])
    end

    it "is refused to a non-admin" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      sign_in_as(create(:user))

      expect { post renew_admin_user_api_token_path(sa, token) }.not_to change(ApiToken, :count)
      expect { post reissue_admin_user_api_token_path(sa, token) }.not_to change(ApiToken, :count)
      expect(ApiToken.exists?(token.id)).to be true
    end

    it "shows each token's status, limits and the never-expiring notice" do
      legacy = ApiToken.generate!(user: sa, name: "legacy", expires_at: 1.day.from_now)
      legacy.update_column(:expires_at, nil)

      get admin_service_account_path(sa)

      expect(response.body).to include("Never expires")
      expect(response.body).to include("This account holds a token that never expires")
      expect(response.body).to include("Evidence: Write")
      expect(response.body).to include(renew_admin_user_api_token_path(sa, token))
    end
  end

  describe "the admin user page" do
    it "refuses Never for a service account's token" do
      sa = create(:user, :service_account, owner: owner)

      expect {
        post admin_user_api_tokens_path(sa),
             params: { api_token: { name: "x", expires_in_days: "0", allowed_endpoints: [ "*" ] }, endpoint_picker: "1" }
      }.not_to change(ApiToken, :count)
      expect(flash[:error]).to include("required for a service account's token")
    end

    it "still lets a person's token never expire, and flags it" do
      person = create(:user)

      post admin_user_api_tokens_path(person),
           params: { api_token: { name: "x", expires_in_days: "0", allowed_endpoints: [ "*" ] }, endpoint_picker: "1" }

      expect(person.api_tokens.sole.expires_at).to be_nil
      get admin_user_path(person)
      expect(response.body).to include("Never expires")
    end
  end

  describe "local sign-in with an email a service account shares" do
    let(:password) { "Shared-Mailbox-Pwd-1" } # gitleaks:allow

    before do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
      RSpec::Mocks.space.proxy_for(ApplicationController).reset
    end

    it "signs the person in, not the service account" do
      create(:user, :service_account, owner: owner, email: "shared@example.com")
      person = create(:user, email: "shared@example.com", password: password, password_confirmation: password,
                             must_reset_password: false, password_changed_at: Time.current)

      post login_path, params: { email: "shared@example.com", password: password }

      expect(session[:user_id]).to eq(person.id)
    end

    it "still refuses, and audits, a service account's email at the sign-in form" do
      sa = create(:user, :service_account, owner: owner, email: "only-bot@example.com")

      post login_path, params: { email: "only-bot@example.com", password: "anything-at-all" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(AuditEvent.where(action: "login_failure", user: sa).last.metadata["reason"])
        .to eq("service_account_web_login")
    end
  end
end
