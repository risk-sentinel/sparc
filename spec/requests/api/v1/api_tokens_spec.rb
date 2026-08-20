# frozen_string_literal: true

require "rails_helper"

# #1016 — issuing and revoking API tokens through the API.
#
# Authorization is asserted in BOTH directions throughout. An allow-leg-only
# spec passes against an endpoint with no guard at all, which is how #919 and
# #974 were found.
RSpec.describe "Api::V1::ApiTokens", type: :request do
  let(:admin)        { create(:user, :admin) }
  let(:non_admin)    { create(:user) }
  let(:subject_user) { create(:user) }

  let(:admin_headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'Admin').plaintext_token}" }
  end
  let(:non_admin_headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: non_admin, name: 'User').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "POST /api/v1/users/:user_id/api_tokens" do
    it "issues a token and returns the plaintext exactly once" do
      expect {
        post api_v1_user_api_tokens_path(subject_user),
          params: { api_token: { name: "CI Pipeline" } }, headers: admin_headers, as: :json
      }.to change { subject_user.api_tokens.count }.by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["name"]).to eq("CI Pipeline")
      expect(data["token"]).to start_with("sparc_")
      expect(data["warning"]).to match(/cannot be retrieved again/i)

      # The plaintext is not recoverable: only the digest is stored, so the
      # issued value must authenticate and must not appear in any later read.
      expect(ApiToken.authenticate(data["token"])).to eq(subject_user.api_tokens.last)

      get api_v1_user_api_tokens_path(subject_user), headers: admin_headers
      expect(response.body).not_to include(data["token"])
    end

    it "names the token when the caller does not" do
      post api_v1_user_api_tokens_path(subject_user),
        params: { api_token: {} }, headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "name")).to be_present
    end

    it "sets an expiry from expires_in_days" do
      post api_v1_user_api_tokens_path(subject_user),
        params: { api_token: { name: "Short lived", expires_in_days: 7 } },
        headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      expires_at = Time.zone.parse(response.parsed_body.dig("data", "expires_at"))
      expect(expires_at).to be_within(1.minute).of(7.days.from_now)
    end

    it "leaves the token non-expiring when expires_in_days is absent" do
      post api_v1_user_api_tokens_path(subject_user),
        params: { api_token: { name: "Long lived" } }, headers: admin_headers, as: :json

      expect(response.parsed_body.dig("data", "expires_at")).to be_nil
      expect(subject_user.api_tokens.last.expires_at).to be_nil
    end

    it "refuses a non-admin, and issues nothing" do
      expect {
        post api_v1_user_api_tokens_path(subject_user),
          params: { api_token: { name: "Should not exist" } },
          headers: non_admin_headers, as: :json
      }.not_to change { subject_user.api_tokens.count }

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an unauthenticated caller" do
      post api_v1_user_api_tokens_path(subject_user),
        params: { api_token: { name: "Anonymous" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a field it does not accept rather than discarding it" do
      post api_v1_user_api_tokens_path(subject_user),
        params: { api_token: { name: "Bad", token_digest: "injected" } },
        headers: admin_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join(" ")).to include("token_digest")
    end
  end

  describe "GET /api/v1/users/:user_id/api_tokens" do
    it "lists metadata and never a token value" do
      created = ApiToken.generate!(user: subject_user, name: "Existing")

      get api_v1_user_api_tokens_path(subject_user), headers: admin_headers

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body["data"]
      expect(rows.map { |r| r["name"] }).to include("Existing")
      expect(response.body).not_to include(created.plaintext_token)
    end

    it "refuses a non-admin" do
      get api_v1_user_api_tokens_path(subject_user), headers: non_admin_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/users/:user_id/api_tokens/:id" do
    it "revokes the token, and it stops authenticating" do
      token = ApiToken.generate!(user: subject_user, name: "Doomed")
      plaintext = token.plaintext_token

      expect {
        delete api_v1_user_api_token_path(subject_user, token), headers: admin_headers
      }.to change { subject_user.api_tokens.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "revoked")).to be(true)
      # Revoked means revoked, not merely absent from a list.
      expect(ApiToken.authenticate(plaintext)).to be_nil
    end

    it "refuses a non-admin, and the token still authenticates afterwards" do
      token = ApiToken.generate!(user: subject_user, name: "Survivor")
      plaintext = token.plaintext_token

      delete api_v1_user_api_token_path(subject_user, token), headers: non_admin_headers

      expect(response).to have_http_status(:forbidden)
      expect(ApiToken.authenticate(plaintext)).to eq(token)
    end

    it "404s for a token belonging to a different user" do
      other = create(:user)
      token = ApiToken.generate!(user: other, name: "Someone else's")

      delete api_v1_user_api_token_path(subject_user, token), headers: admin_headers

      expect(response).to have_http_status(:not_found)
      expect(ApiToken.authenticate(token.plaintext_token)).to eq(token)
    end
  end
end
