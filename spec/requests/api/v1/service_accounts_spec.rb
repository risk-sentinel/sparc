# frozen_string_literal: true

require "rails_helper"

# #1013 — service accounts through the API.
#
# The properties that matter are credential properties: the issued token WORKS,
# a rotation leaves the old one dead, and a disabled account cannot act. A spec
# that only checked response shapes would pass against an endpoint that handed
# back strings nothing accepts.
RSpec.describe "Api::V1::ServiceAccounts", type: :request do
  let(:admin)     { create(:user, :admin) }
  let(:non_admin) { create(:user) }
  let(:owner)     { create(:user) }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:valid_attributes) do
    { email: "pipeline-#{SecureRandom.hex(4)}@example.com", first_name: "Build",
      last_name: "Pipeline", display_name: "Build Pipeline", owner_id: owner.id }
  end

  describe "POST /api/v1/service_accounts" do
    it "creates the account and issues a working token in one call" do
      expect {
        post api_v1_service_accounts_path, params: { service_account: valid_attributes },
          headers: headers_for(admin), as: :json
      }.to change { User.service_accounts.count }.by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]

      expect(data["service_account"]).to be(true)
      expect(data["token"]).to start_with("sparc_sa_")
      expect(data["warning"]).to match(/cannot be retrieved again/i)

      # The credential is real, not merely present in the response.
      authenticated = ApiToken.authenticate(data["token"])
      expect(authenticated).to be_present
      expect(authenticated.user.id).to eq(data["id"])
    end

    it "defaults the token to a 90-day expiry rather than never expiring" do
      post api_v1_service_accounts_path, params: { service_account: valid_attributes },
        headers: headers_for(admin), as: :json

      expires_at = Time.zone.parse(response.parsed_body.dig("data", "token_expires_at"))
      expect(expires_at).to be_within(1.hour).of(90.days.from_now)
    end

    it "accepts endpoint and CIDR allowlists as JSON arrays" do
      post api_v1_service_accounts_path,
        params: { service_account: valid_attributes.merge(
          expires_in_days: 30,
          allowed_endpoints: [ "/api/v1/evidences" ],
          allowed_cidrs: [ "10.0.0.0/8" ]
        ) },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:created)
      token = ApiToken.authenticate(response.parsed_body.dig("data", "token"))
      expect(token.allowed_endpoints).to eq([ "/api/v1/evidences" ])
      expect(token.allowed_cidrs).to eq([ "10.0.0.0/8" ])
    end

    it "does not make a service account an admin unless asked" do
      post api_v1_service_accounts_path, params: { service_account: valid_attributes },
        headers: headers_for(admin), as: :json

      expect(response.parsed_body.dig("data", "admin")).to be(false)
    end

    it "refuses a non-admin, and creates nothing" do
      expect {
        post api_v1_service_accounts_path, params: { service_account: valid_attributes },
          headers: headers_for(non_admin), as: :json
      }.not_to change { User.service_accounts.count }

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an unauthenticated caller" do
      post api_v1_service_accounts_path, params: { service_account: valid_attributes }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a field it does not accept rather than discarding it" do
      post api_v1_service_accounts_path,
        params: { service_account: valid_attributes.merge(password: "hunter2") },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join(" ")).to include("password")
    end
  end

  describe "POST /api/v1/service_accounts/:id/regenerate_token" do
    let!(:account) do
      post api_v1_service_accounts_path, params: { service_account: valid_attributes },
        headers: headers_for(admin), as: :json
      response.parsed_body["data"]
    end

    it "kills every previous token — rotation that leaves the old one working is not rotation" do
      old_token = account["token"]
      expect(ApiToken.authenticate(old_token)).to be_present

      post regenerate_token_api_v1_service_account_path(account["id"]),
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      new_token = response.parsed_body.dig("data", "token")

      expect(new_token).not_to eq(old_token)
      expect(ApiToken.authenticate(new_token)).to be_present
      expect(ApiToken.authenticate(old_token)).to be_nil
      expect(response.parsed_body.dig("data", "tokens_revoked")).to eq(1)
    end

    it "refuses a non-admin, and the existing token still works" do
      old_token = account["token"]

      post regenerate_token_api_v1_service_account_path(account["id"]),
        headers: headers_for(non_admin), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ApiToken.authenticate(old_token)).to be_present
    end
  end

  describe "disable and enable" do
    let(:account) { create(:user, :service_account) }

    it "disables and re-enables, and the status is readable both times" do
      post disable_api_v1_service_account_path(account),
        params: { reason: "key rotation overdue" }, headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(account.reload.status).not_to eq("active")

      post enable_api_v1_service_account_path(account), headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(account.reload.status).to eq("active")
    end

    it "refuses a non-admin, and the account stays active" do
      post disable_api_v1_service_account_path(account),
        headers: headers_for(non_admin), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(account.reload.status).to eq("active")
    end
  end

  describe "GET /api/v1/service_accounts" do
    it "lists only service accounts, never human users" do
      create(:user, :service_account)
      human = create(:user)

      get api_v1_service_accounts_path, params: { items: 100 }, headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |r| r["id"] }
      expect(ids).not_to include(human.id)
      expect(response.parsed_body["data"]).to all(include("service_account" => true))
    end

    it "never returns a token value" do
      account = create(:user, :service_account)
      token = ApiToken.generate!(user: account, name: "Existing")

      get api_v1_service_account_path(account), headers: headers_for(admin)

      expect(response.body).not_to include(token.plaintext_token)
    end

    it "refuses a non-admin" do
      get api_v1_service_accounts_path, headers: headers_for(non_admin)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/service_accounts/:id" do
    it "deactivates rather than deleting, so the audit trail survives" do
      account = create(:user, :service_account)
      # Built BEFORE the block: a lazy `let` first named inside the assertion
      # creates its record during the measurement and moves the count itself.
      headers = headers_for(admin)

      expect {
        delete api_v1_service_account_path(account), headers: headers
      }.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "deactivated")).to be(true)
      expect(account.reload.status).not_to eq("active")
    end

    it "refuses a non-admin, and the account stays active" do
      account = create(:user, :service_account)

      delete api_v1_service_account_path(account), headers: headers_for(non_admin)

      expect(response).to have_http_status(:forbidden)
      expect(account.reload.status).to eq("active")
    end
  end
end
