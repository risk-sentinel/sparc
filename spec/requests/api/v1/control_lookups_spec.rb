# frozen_string_literal: true

require "rails_helper"

# #902 follow-up — cross-catalog control lookup.
#
# Every other control route is catalog-scoped, which cannot answer "does this
# identifier name a real control?" for a caller that belongs to no catalog —
# the question when linking evidence. Shares ControlLookupService with the
# session-authenticated endpoint the picker uses, so what is offered and what is
# validated cannot drift apart.
RSpec.describe "Api::V1::ControlLookups", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_control_lookups_path
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 without a token on resolve" do
      get api_v1_resolve_control_lookup_path, params: { id: "ac-2" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/controls" do
    it "searches across catalogs" do
      ensure_control("ac-2")

      get api_v1_control_lookups_path, params: { q: "ac-2" }, headers: admin_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].map { |c| c["control_id"] }).to include("ac-2")
      expect(body["meta"]).to include("total", "limit", "scoped_to_profile")
    end

    it "finds a control by the padded form SPARC displays" do
      ensure_control("si-4")

      get api_v1_control_lookups_path, params: { q: "SI-04" }, headers: admin_headers

      expect(JSON.parse(response.body)["data"].map { |c| c["control_id"] }).to include("si-4")
    end

    it "clamps an absurd limit rather than dumping the catalog" do
      family = create(:control_family, code: "AC")
      5.times { |n| create(:catalog_control, control_family: family, control_id: "ac-#{n + 1}") }

      get api_v1_control_lookups_path, params: { q: "ac-", limit: 10_000 }, headers: admin_headers

      expect(JSON.parse(response.body)["meta"]["limit"]).to eq(ControlLookupService::MAX_LIMIT)
    end
  end

  describe "GET /api/v1/controls/resolve" do
    it "resolves any of the three legitimate forms to the canonical one" do
      ensure_control("ac-2.1")

      %w[ac-2.1 AC-02.01].each do |form|
        get api_v1_resolve_control_lookup_path, params: { id: form }, headers: admin_headers

        expect(response).to have_http_status(:ok), "#{form} did not resolve"
        data = JSON.parse(response.body)["data"]
        expect(data["control_id"]).to eq("ac-2.1")
        expect(data["resolved"]).to be true
      end
    end

    it "404s an identifier that names no control, and says what it looked for" do
      ensure_control("ac-2")

      get api_v1_resolve_control_lookup_path, params: { id: unknown_control_id }, headers: admin_headers

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/unknown control/i)
      expect(body["data"]["resolved"]).to be false
      expect(body["data"]["canonical"]).to eq(ControlId.canonical(unknown_control_id))
    end
  end
end
