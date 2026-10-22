# frozen_string_literal: true

require "rails_helper"

# #1233 — a token's endpoint and CIDR limits are changed IN PLACE, without
# reissuing it (owner, 2026-10-21; admin only). Before, the only way to widen or
# narrow what a service account could reach was Regenerate, which revoked every
# token and made every client swap credentials.
#
# Both directions throughout: an admin can, a non-admin cannot; a widening and a
# narrowing each take effect on the token's very next request.
RSpec.describe "Editing a token's limits in place (#1233)", type: :request do
  let(:admin)     { create(:user, :admin) }
  let(:non_admin) { create(:user) }
  # An admin service account, so its role permissions allow every endpoint and
  # only the token's limits decide what it reaches.
  let(:account)   { create(:user, :admin, :service_account) }
  let!(:token) do
    ApiToken.generate!(user: account, name: "ci", expires_at: 30.days.from_now,
                       allowed_endpoints: [ "ssp_documents:read" ], allowed_cidrs: [ "10.0.0.0/8" ])
  end
  let!(:admin_headers) { bearer(admin) }

  def bearer(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'caller', expires_at: 1.day.from_now).plaintext_token}" }
  end

  def as_token = { "Authorization" => "Bearer #{token.plaintext_token}" }

  def patch_limits(headers, **fields)
    patch api_v1_user_api_token_path(account, token), params: { api_token: fields }, headers: headers, as: :json
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:api_auth_mode).and_return("local")
  end

  describe "PATCH /api/v1/users/:user_id/api_tokens/:id" do
    it "changes the limits and keeps the token's value" do
      digest = token.token_digest

      patch_limits(admin_headers, allowed_endpoints: [ "control_catalogs:read" ], allowed_cidrs: [])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "allowed_endpoints")).to eq([ "control_catalogs:read" ])
      expect(response.parsed_body.dig("data", "allowed_cidrs")).to eq([])
      expect(response.parsed_body["data"]).not_to have_key("token")
      expect(token.reload.token_digest).to eq(digest)
    end

    it "keeps a field that is left out" do
      patch_limits(admin_headers, allowed_endpoints: [ "control_catalogs:read" ])

      expect(token.reload.allowed_cidrs).to eq([ "10.0.0.0/8" ])
    end

    it "audits the before and after limits" do
      expect { patch_limits(admin_headers, allowed_endpoints: [ "control_catalogs:read" ]) }
        .to change { AuditEvent.where(action: "api_token_limits_changed").count }.by(1)

      meta = AuditEvent.where(action: "api_token_limits_changed").last.metadata
      expect(meta.dig("before", "allowed_endpoints")).to eq([ "ssp_documents:read" ])
      expect(meta.dig("after", "allowed_endpoints")).to eq([ "control_catalogs:read" ])
      expect(meta["token_id"]).to eq(token.id)
    end

    it "refuses an unknown entry, as creation does, and changes nothing" do
      patch_limits(admin_headers, allowed_endpoints: [ "nope:read" ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(token.reload.allowed_endpoints).to eq([ "ssp_documents:read" ])
    end

    it "refuses any other field" do
      patch_limits(admin_headers, name: "renamed")

      expect(response).to have_http_status(:unprocessable_content)
      expect(token.reload.name).to eq("ci")
    end

    it "refuses an expired token" do
      token.update_columns(expires_at: 1.minute.ago)

      patch_limits(admin_headers, allowed_endpoints: [ "control_catalogs:read" ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(token.reload.allowed_endpoints).to eq([ "ssp_documents:read" ])
    end

    it "is refused to a non-admin, and changes nothing" do
      patch_limits(bearer(non_admin), allowed_endpoints: [])

      expect(response).to have_http_status(:forbidden)
      expect(token.reload.allowed_endpoints).to eq([ "ssp_documents:read" ])
    end
  end

  describe "the change applies from the token's next request" do
    before { token.update_columns(allowed_cidrs: []) }

    it "widens: an endpoint refused before is allowed after" do
      get api_v1_control_catalogs_path, headers: as_token
      expect(response).to have_http_status(:forbidden)

      patch_limits(admin_headers, allowed_endpoints: [ "ssp_documents:read", "control_catalogs:read" ])

      get api_v1_control_catalogs_path, headers: as_token
      expect(response).to have_http_status(:ok)
    end

    it "narrows: an endpoint allowed before is refused after" do
      get api_v1_ssp_documents_path, headers: as_token
      expect(response).to have_http_status(:ok)

      patch_limits(admin_headers, allowed_endpoints: [ "control_catalogs:read" ])

      get api_v1_ssp_documents_path, headers: as_token
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the web form" do
    it "lets an admin change the limits from the account page" do
      sign_in_as(admin)

      get edit_admin_user_api_token_path(account, token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="ssp_documents:read" checked').or include("ssp_documents:read")

      patch admin_user_api_token_path(account, token), params: {
        endpoint_picker: "1",
        api_token: { allowed_endpoints: [ "", "control_catalogs:read" ], allowed_cidrs: "192.168.0.0/16" }
      }

      expect(response).to redirect_to(admin_service_account_path(account))
      expect(token.reload.allowed_endpoints).to eq([ "control_catalogs:read" ])
      expect(token.allowed_cidrs).to eq([ "192.168.0.0/16" ])
      expect(AuditEvent.where(action: "api_token_limits_changed").count).to eq(1)
    end

    it "refuses an empty picker rather than reading it as every endpoint" do
      sign_in_as(admin)

      patch admin_user_api_token_path(account, token), params: {
        endpoint_picker: "1", api_token: { allowed_endpoints: [ "" ], allowed_cidrs: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(token.reload.allowed_endpoints).to eq([ "ssp_documents:read" ])
    end

    it "offers Edit limits on the account page" do
      sign_in_as(admin)

      get admin_service_account_path(account)

      expect(response.body).to include(edit_admin_user_api_token_path(account, token))
    end

    it "offers Edit limits on a person's admin page too" do
      person = create(:user)
      own = ApiToken.generate!(user: person, name: "laptop")
      sign_in_as(admin)

      get admin_user_path(person)

      expect(response.body).to include(edit_admin_user_api_token_path(person, own))
    end

    it "is refused to a non-admin, and changes nothing" do
      sign_in_as(non_admin)

      get edit_admin_user_api_token_path(account, token)
      expect(response).not_to have_http_status(:ok)

      patch admin_user_api_token_path(account, token), params: {
        endpoint_picker: "1", api_token: { allowed_endpoints: [ "control_catalogs:read" ] }
      }
      expect(token.reload.allowed_endpoints).to eq([ "ssp_documents:read" ])
    end
  end
end
