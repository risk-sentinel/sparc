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

  # #1022 — the API-wide pagination convention must actually NARROW here.
  #
  # This is the largest collection in the API (4,054 controls) and it accepted
  # only its own `?limit`. A caller using `?items` — which every other index
  # honours — got 25 rows and an envelope reporting `limit: 25`, so the response
  # looked like a correct answer rather than an ignored parameter.
  #
  # Asserting on the ROW COUNT, not on the envelope: the envelope was already
  # self-consistent while the parameter was being dropped, which is precisely how
  # this survived the #995 sweep.
  describe "GET /api/v1/controls — pagination convention (#1022)" do
    before do
      catalog = create(:control_catalog)
      family  = create(:control_family, control_catalog: catalog)
      5.times { |i| create(:catalog_control, control_family: family, control_id: "ac-#{i + 1}") }
    end

    it "narrows on ?items, like every other index" do
      get api_v1_control_lookups_path, params: { items: 2 }, headers: admin_headers

      body = JSON.parse(response.body)
      expect(body["data"].length).to eq(2)
      expect(body.dig("meta", "limit")).to eq(2)
    end

    it "narrows on ?per_page too" do
      get api_v1_control_lookups_path, params: { per_page: 3 }, headers: admin_headers

      expect(JSON.parse(response.body)["data"].length).to eq(3)
    end

    it "still honours ?limit — the published contract for this endpoint" do
      get api_v1_control_lookups_path, params: { limit: 1 }, headers: admin_headers

      expect(JSON.parse(response.body)["data"].length).to eq(1)
    end

    it "prefers ?limit when both are given, so existing callers do not change" do
      get api_v1_control_lookups_path, params: { limit: 1, items: 4 }, headers: admin_headers

      expect(JSON.parse(response.body)["data"].length).to eq(1)
    end

    it "offers ?page, so rows past the first page are reachable" do
      get api_v1_control_lookups_path, params: { items: 2, page: 2 }, headers: admin_headers

      body = JSON.parse(response.body)
      expect(body.dig("meta", "page")).to eq(2)
      expect(body.dig("meta", "pages")).to be >= 2
      expect(body["data"].length).to eq(2)
    end

    it "returns disjoint rows across pages" do
      get api_v1_control_lookups_path, params: { items: 2, page: 1 }, headers: admin_headers
      first = JSON.parse(response.body)["data"].map { |c| c["id"] || c["control_id"] }
      get api_v1_control_lookups_path, params: { items: 2, page: 2 }, headers: admin_headers
      second = JSON.parse(response.body)["data"].map { |c| c["id"] || c["control_id"] }

      expect(first & second).to be_empty,
        "a row appeared on two pages — paging over an unordered scope is unstable (#1022)"
    end

    it "returns the SAME page on two identical requests" do
      2.times.map do
        get api_v1_control_lookups_path, params: { items: 3, page: 2 }, headers: admin_headers
        JSON.parse(response.body)["data"].map { |c| c["id"] || c["control_id"] }
      end => [ first, second ]

      expect(first).to eq(second),
        "the same request returned different rows — the scope has no deterministic order"
    end

    it "counts DISTINCT identifiers, not table rows" do
      get api_v1_control_lookups_path, params: { items: 1 }, headers: admin_headers

      body = JSON.parse(response.body)
      # 5 controls created above, all distinct identifiers.
      expect(body.dig("meta", "total")).to eq(5)
      expect(body.dig("meta", "pages")).to eq(5)
    end

    it "treats page 0 and negative pages as page 1" do
      get api_v1_control_lookups_path, params: { items: 2, page: 0 }, headers: admin_headers
      expect(JSON.parse(response.body).dig("meta", "page")).to eq(1)
    end

    it "cannot be used to request the whole table" do
      get api_v1_control_lookups_path, params: { items: 999_999 }, headers: admin_headers

      # ControlLookupService clamps to MAX_LIMIT; the point is that a caller
      # cannot turn the convention into an unbounded query (#549).
      expect(JSON.parse(response.body)["data"].length).to be <= 100
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
