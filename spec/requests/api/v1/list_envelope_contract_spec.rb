# frozen_string_literal: true

require "rails_helper"

# #1019 — every list endpoint publishes the same envelope.
#
# Five of them did not: three returned `{data: [...]}` with no `meta` at all,
# one carried only a count, and `ksi_catalog#mappings` returned a DIFFERENT
# shape when its collection was empty than when it was populated — which breaks
# a client precisely in the case least likely to exist while the client is
# being written.
#
# Written as one contract across the five rather than a paragraph in each of
# five files, because the defect was that they disagreed, and five separate
# specs is the arrangement that let them.
RSpec.describe "Api::V1 list envelope contract", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  REQUIRED_META = %w[page pages count items].freeze

  def expect_standard_envelope(response)
    expect(response).to have_http_status(:ok), response.body

    body = response.parsed_body
    expect(body["data"]).to be_an(Array), "expected a list, got #{body['data'].class}"
    expect(body).to have_key("meta"), "a list endpoint returned no `meta`: #{response.body[0, 200]}"
    expect(body["meta"].keys).to include(*REQUIRED_META),
      "`meta` is missing #{REQUIRED_META - body['meta'].keys}: #{body['meta']}"
    expect(body["meta"]["count"]).to eq(body["data"].size),
      "`meta.count` disagrees with the number of rows returned"
    body
  end

  describe "GET /api/v1/guides" do
    it "returns the standard envelope" do
      get api_v1_guides_path, headers: headers
      expect_standard_envelope(response)
    end
  end

  describe "GET /api/v1/admin/remediation_timelines" do
    it "returns the standard envelope" do
      get api_v1_admin_remediation_timelines_path, headers: headers
      expect_standard_envelope(response)
    end
  end

  describe "GET /api/v1/back_matter_resources/promotion_queue" do
    it "returns the standard envelope when the queue is empty" do
      get promotion_queue_api_v1_back_matter_resources_path, headers: headers
      expect_standard_envelope(response)
    end
  end

  describe "KSI catalog" do
    let!(:ksi_catalog) do
      create(:control_catalog, name: "FedRAMP 20x Key Security Indicators", source: "FedRAMP 20x")
    end

    it "GET /api/v1/ksi_catalog/themes returns the standard envelope" do
      create(:control_family, control_catalog: ksi_catalog, code: "AUTH", sort_order: 1)

      get themes_api_v1_ksi_catalog_path, headers: headers
      body = expect_standard_envelope(response)
      expect(body["data"].size).to eq(1)
    end

    # The defect, asserted in BOTH states. A client reading `meta.count` worked
    # against a seeded instance and broke against a fresh one.
    it "GET /api/v1/ksi_catalog/mappings returns the standard envelope when EMPTY" do
      expect(ControlMapping.find_by(source_catalog: ksi_catalog)).to be_nil

      get mappings_api_v1_ksi_catalog_path, headers: headers
      body = expect_standard_envelope(response)

      expect(body["data"]).to eq([])
      expect(body["meta"]["count"]).to eq(0)
      # The explanation survives — it is additional, not a replacement.
      expect(body["meta"]["message"]).to match(/No KSI-to-NIST mapping/)
    end

    it "GET /api/v1/ksi_catalog/mappings returns the SAME envelope when populated" do
      mapping = create(:control_mapping, source_catalog: ksi_catalog)
      mapping.control_mapping_entries.create!(source_control_id: "KSI-CNA-01",
                                              target_control_id: "AC-1",
                                              relationship: "equal")

      get mappings_api_v1_ksi_catalog_path, headers: headers
      body = expect_standard_envelope(response)

      expect(body["data"].size).to eq(1)
      expect(body["meta"]["count"]).to eq(1)
    end
  end
end
