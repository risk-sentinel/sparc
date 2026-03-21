# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::KsiCatalog", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  let!(:ksi_catalog) do
    create(:control_catalog, name: "FedRAMP 20x Key Security Indicators", source: "FedRAMP 20x", version: "1.0.0")
  end
  let!(:theme_iam) { create(:control_family, control_catalog: ksi_catalog, code: "IAM", name: "Identity and Access Management", sort_order: 1) }
  let!(:theme_mla) { create(:control_family, control_catalog: ksi_catalog, code: "MLA", name: "Monitoring, Logging, and Auditing", sort_order: 2) }
  let!(:ksi_iam_01) do
    create(:catalog_control, control_family: theme_iam, control_id: "ksi-iam-01",
      title: "Phishing-Resistant MFA", description: "All user accounts are protected with phishing-resistant MFA.",
      baseline_impact: "LOW, MODERATE",
      guidance_data: { "validation_frequency" => "weekly", "evidence_type" => "machine", "automation_required" => true })
  end
  let!(:ksi_iam_02) do
    create(:catalog_control, control_family: theme_iam, control_id: "ksi-iam-02",
      title: "Least Privilege Access", baseline_impact: "LOW, MODERATE")
  end
  let!(:ksi_mla_01) do
    create(:catalog_control, control_family: theme_mla, control_id: "ksi-mla-01",
      title: "Centralized Logging", baseline_impact: "LOW, MODERATE")
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get themes_api_v1_ksi_catalog_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/ksi_catalog/themes" do
    it "returns all KSI themes" do
      get themes_api_v1_ksi_catalog_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["data"].first["code"]).to eq("IAM")
      expect(parsed["data"].first["indicators_count"]).to eq(2)
    end
  end

  describe "GET /api/v1/ksi_catalog/indicators" do
    it "returns all KSI indicators with pagination" do
      get indicators_api_v1_ksi_catalog_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(3)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by theme" do
      get indicators_api_v1_ksi_catalog_path, params: { theme: "IAM" }, headers: auth_headers

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["data"].all? { |d| d["theme_code"] == "IAM" }).to be true
    end

    it "filters by impact_level" do
      create(:catalog_control, control_family: theme_iam, control_id: "ksi-iam-high",
        title: "High Only", baseline_impact: "MODERATE")

      get indicators_api_v1_ksi_catalog_path, params: { impact_level: "LOW" }, headers: auth_headers

      parsed = JSON.parse(response.body)
      ids = parsed["data"].map { |d| d["control_id"] }
      expect(ids).not_to include("ksi-iam-high")
    end
  end

  describe "GET /api/v1/ksi_catalog/indicators/:id" do
    it "returns a single KSI with details" do
      get indicator_api_v1_ksi_catalog_path(id: "ksi-iam-01"), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["control_id"]).to eq("ksi-iam-01")
      expect(parsed["data"]["description"]).to be_present
      expect(parsed["data"]["validation_frequency"]).to eq("weekly")
      expect(parsed["data"]["automation_required"]).to be true
    end

    it "includes mapped NIST controls when mapping exists" do
      nist_catalog = create(:control_catalog, name: "NIST SP 800-53 Rev 5", source: "NIST")
      mapping = create(:control_mapping,
        source_catalog: ksi_catalog, target_catalog: nist_catalog,
        name: "KSI to NIST", status: "complete", method_type: "human", matching_rationale: "functional")
      create(:control_mapping_entry, control_mapping: mapping,
        source_control_id: "ksi-iam-01", target_control_id: "ia-2", relationship: "superset")

      get indicator_api_v1_ksi_catalog_path(id: "ksi-iam-01"), headers: auth_headers

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["mapped_nist_controls"].length).to eq(1)
      expect(parsed["data"]["mapped_nist_controls"].first["target"]).to eq("ia-2")
    end

    it "returns 404 for unknown KSI" do
      get indicator_api_v1_ksi_catalog_path(id: "ksi-xxx-99"), headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/ksi_catalog/mappings" do
    it "returns empty when no mapping exists" do
      get mappings_api_v1_ksi_catalog_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]).to eq([])
    end

    it "returns mapping entries when mapping exists" do
      nist_catalog = create(:control_catalog, name: "NIST SP 800-53 Rev 5", source: "NIST")
      mapping = create(:control_mapping,
        source_catalog: ksi_catalog, target_catalog: nist_catalog,
        name: "KSI to NIST", status: "complete", method_type: "human", matching_rationale: "functional")
      create(:control_mapping_entry, control_mapping: mapping,
        source_control_id: "ksi-iam-01", target_control_id: "ia-2",
        relationship: "superset", row_order: 0)

      get mappings_api_v1_ksi_catalog_path, headers: auth_headers

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["source_control_id"]).to eq("ksi-iam-01")
      expect(parsed["meta"]["mapping_name"]).to eq("KSI to NIST")
    end
  end

  context "as a non-admin user" do
    let(:regular_user) { create(:user) }
    let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
    let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

    it "can access all read-only endpoints" do
      get themes_api_v1_ksi_catalog_path, headers: user_headers
      expect(response).to have_http_status(:ok)

      get indicators_api_v1_ksi_catalog_path, headers: user_headers
      expect(response).to have_http_status(:ok)
    end
  end
end
