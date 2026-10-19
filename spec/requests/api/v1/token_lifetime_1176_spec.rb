# frozen_string_literal: true

require "rails_helper"

# #1176 — token lifetime, renewal, reissue, per-resource Read/Write limits and
# the endpoint catalog, through the API. Authorization in both directions.
RSpec.describe "API token lifetime and limits (#1176)", type: :request do
  let(:admin)     { create(:user, :admin) }
  let(:non_admin) { create(:user) }
  let(:person)    { create(:user) }
  let(:account)   { create(:user, :service_account) }

  def bearer(user, **opts)
    token = ApiToken.generate!(user: user, name: "caller", expires_at: 1.day.from_now, **opts)
    { "Authorization" => "Bearer #{token.plaintext_token}" }
  end

  # Eager: a lazy caller token would be created INSIDE the `change` blocks
  # below and count as the change they assert did not happen.
  let!(:admin_headers) { bearer(admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:api_auth_mode).and_return("local")
  end

  describe "POST /api/v1/users/:user_id/api_tokens" do
    def issue(user, **fields)
      post api_v1_user_api_tokens_path(user), params: { api_token: fields }, headers: admin_headers, as: :json
    end

    it "gives a service account's token the default lifetime when none is asked for" do
      issue(account, name: "ci")

      expect(response).to have_http_status(:created)
      expect(Time.zone.parse(response.parsed_body.dig("data", "expires_at")))
        .to be_within(1.minute).of(ApiToken::DEFAULT_SERVICE_ACCOUNT_DAYS.days.from_now)
    end

    it "refuses a never-expiring token for a service account" do
      expect { issue(account, expires_in_days: 0) }.not_to change(ApiToken, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to include("required for a service account's token")
    end

    it "refuses a service account's token past SPARC_API_TOKEN_MAX_DAYS" do
      allow(SparcConfig).to receive(:api_token_max_days).and_return(30)

      expect { issue(account, expires_in_days: 31) }.not_to change(ApiToken, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "still issues a person a never-expiring token" do
      issue(person, expires_in_days: 0)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["data"]).to include("expires_at" => nil, "never_expires" => true)
    end

    it "refuses a lifetime that is not a whole number of days instead of reading it as never" do
      expect { issue(person, expires_in_days: "soon") }.not_to change(ApiToken, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts catalog entries and CIDRs, and reports them" do
      issue(person, allowed_endpoints: [ "ssp_documents:read" ], allowed_cidrs: [ "10.0.0.0/8" ])

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["allowed_endpoints"]).to eq([ "ssp_documents:read" ])
      expect(data["allowed_endpoints_summary"]).to eq([ "System security plans (SSP): Read" ])
      expect(data["allowed_cidrs"]).to eq([ "10.0.0.0/8" ])
    end

    it "refuses an endpoint entry that names nothing" do
      expect { issue(person, allowed_endpoints: [ "/api/v1/nowhere*" ]) }.not_to change(ApiToken, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to include("matches no API route")
    end
  end

  describe "renew and reissue" do
    let!(:token) do
      ApiToken.generate!(user: account, name: "pipeline", expires_at: 40.days.from_now,
                         allowed_endpoints: [ "evidences:write" ], allowed_cidrs: [ "10.0.0.0/8" ])
    end

    it "renews: a new token with the same limits, the old one alive for the grace window" do
      allow(SparcConfig).to receive(:api_token_renewal_grace_days).and_return(7)

      expect {
        post renew_api_v1_user_api_token_path(account, token), headers: admin_headers, as: :json
      }.to change { account.api_tokens.count }.by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["token"]).to start_with("sparc_sa_")
      expect(data["allowed_endpoints"]).to eq([ "evidences:write" ])
      expect(data["allowed_cidrs"]).to eq([ "10.0.0.0/8" ])
      expect(Time.zone.parse(data["replaced_token_expires_at"])).to be_within(1.minute).of(7.days.from_now)
      expect(ApiToken.authenticate(token.plaintext_token)).to eq(token)
      expect(AuditEvent.where(action: "api_token_renewed").last.metadata)
        .to include("replaced_token_id" => token.id, "new_token_id" => data["id"])
    end

    it "reissues: the old token stops at once, the new one keeps the limits" do
      post reissue_api_v1_user_api_token_path(account, token), headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(ApiToken.authenticate(token.plaintext_token)).to be_nil
      expect(response.parsed_body.dig("data", "allowed_endpoints")).to eq([ "evidences:write" ])
      expect(AuditEvent.where(action: "api_token_reissued").last.metadata)
        .to include("revoked_token_id" => token.id)
    end

    it "is refused to a non-admin, changing nothing" do
      headers = bearer(non_admin)
      %w[renew reissue].each do |action|
        expect {
          post send("#{action}_api_v1_user_api_token_path", account, token), headers: headers, as: :json
        }.not_to change(ApiToken, :count)
        expect(response).to have_http_status(:forbidden)
      end
      expect(token.reload.expires_at).to be_within(1.minute).of(40.days.from_now)
    end
  end

  describe "Read / Write enforcement on a real request" do
    let!(:ssp) { create(:ssp_document) }
    # An admin service account (#536), so the document's own authorization
    # passes and the token's endpoint limit is the only thing that can refuse.
    let(:account) { create(:user, :service_account, admin: true) }

    it "lets a Read token fetch, and stops it writing" do
      headers = bearer(account, allowed_endpoints: [ "ssp_documents:read" ])

      get api_v1_ssp_document_path(ssp), headers: headers
      expect(response).to have_http_status(:ok)

      delete api_v1_ssp_document_path(ssp), headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("Token is not authorized for this endpoint")
      expect(SspDocument.exists?(ssp.id)).to be true
    end

    it "lets a Write-only token change, and stops it fetching" do
      headers = bearer(account, allowed_endpoints: [ "ssp_documents:write" ])

      get api_v1_ssp_document_path(ssp), headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("Token is not authorized for this endpoint")
    end

    it "keeps one group's limit off another group" do
      get api_v1_sar_documents_path, headers: bearer(account, allowed_endpoints: [ "ssp_documents:read" ])

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("Token is not authorized for this endpoint")
    end

    it "lets a Read token run a POST that only computes" do
      post "/api/v1/oscal/sar_from_hdf", headers: bearer(account, allowed_endpoints: [ "oscal:read" ]), as: :json

      # Past the endpoint gate: whatever the translation says about an empty
      # body, it is not the token refusal.
      expect(response.parsed_body["error"]).not_to eq("Token is not authorized for this endpoint")
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/api_endpoints" do
    it "lists every group with its levels and the entries to send" do
      get api_v1_api_endpoints_path, headers: admin_headers

      expect(response).to have_http_status(:ok)
      ssp = response.parsed_body["data"].find { |g| g["group"] == "ssp_documents" }
      expect(ssp).to include("access_levels" => %w[read write],
                             "entries" => %w[ssp_documents:read ssp_documents:write])
      expect(response.parsed_body["data"].size).to eq(ApiEndpointCatalog.groups.size)
      expect(response.parsed_body.dig("meta", "all_endpoints")).to eq("*")
    end

    it "is refused to a non-admin" do
      get api_v1_api_endpoints_path, headers: bearer(non_admin)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "service accounts" do
    let!(:owner) { create(:user) }

    def create_account(**token_fields)
      post api_v1_service_accounts_path,
        params: { service_account: { email: "team@example.com", display_name: "bot", owner_id: owner.id, **token_fields } },
        headers: admin_headers, as: :json
    end

    it "creates two accounts that share one team mailbox (option A)" do
      2.times { create_account }

      expect(User.service_accounts.where(email: "team@example.com").count).to eq(2)
    end

    it "creates no account when its first token is refused" do
      expect { create_account(expires_in_days: 0) }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)

      expect { create_account(allowed_endpoints: [ "nope:read" ]) }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "regenerates without widening: limits not sent are carried over" do
      sa = create(:user, :service_account, owner: owner)
      ApiToken.generate!(user: sa, name: "t", expires_at: 30.days.from_now,
                         allowed_endpoints: [ "users:read" ], allowed_cidrs: [ "10.0.0.0/8" ])

      post regenerate_token_api_v1_service_account_path(sa), headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      token = sa.api_tokens.reload.sole
      expect(token.allowed_endpoints).to eq([ "users:read" ])
      expect(token.allowed_cidrs).to eq([ "10.0.0.0/8" ])
    end

    it "reports never-expiring and expiring-soon tokens" do
      sa = create(:user, :service_account, owner: owner)
      old = ApiToken.generate!(user: sa, name: "legacy", expires_at: 1.day.from_now)
      old.update_column(:expires_at, nil)
      ApiToken.generate!(user: sa, name: "soon", expires_at: 5.days.from_now)

      get api_v1_service_account_path(sa), headers: admin_headers

      tokens = response.parsed_body.dig("data", "tokens").index_by { |t| t["name"] }
      expect(tokens["legacy"]).to include("never_expires" => true, "expiring_soon" => false)
      expect(tokens["soon"]).to include("never_expires" => false, "expiring_soon" => true)
    end
  end
end
