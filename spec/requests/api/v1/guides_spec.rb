# frozen_string_literal: true

require "rails_helper"

# #784 — read-only User Guides API backing the in-app Help Center.
RSpec.describe "Api::V1::Guides", type: :request do
  let(:user)    { create(:user) }
  let(:token)   { ApiToken.generate!(user: user, name: "Guides Token") }
  let(:headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  # CI has no SPARC_ENABLE_* vars, so the app runs in open mode where the API
  # skips token auth — enable auth to exercise the 401 path (see discovery_spec
  # and feedback_local_env_vs_ci_drift).
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /api/v1/guides" do
    it "returns the list of guides (slug, title, summary)" do
      get "/api/v1/guides", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["data"]).to be_an(Array)
      expect(body["data"].size).to be >= 13
      entry = body["data"].first
      expect(entry.keys).to contain_exactly("slug", "title", "summary")
      expect(body["data"].map { |g| g["slug"] }).to include("system-security-plans")
    end

    it "requires authentication" do
      get "/api/v1/guides"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/guides/:slug" do
    it "returns a rendered guide" do
      get "/api/v1/guides/system-security-plans", headers: headers

      expect(response).to have_http_status(:ok)
      # #1036 — wrapped in `data`, matching `index` above and every other
      # resource read in this API. It used to come back at the top level, so a
      # client with one response handler got nil here.
      body = response.parsed_body["data"]
      expect(body["slug"]).to eq("system-security-plans")
      expect(body["title"]).to be_present
      expect(body["html"]).to include("<h")
    end

    it "404s on an unknown slug" do
      get "/api/v1/guides/no-such-guide", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
