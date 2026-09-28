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

    # #1194 — the #1115 re-key renamed ten ids in place; an old reference still
    # finds the indicator, and learns its current id.
    it "resolves an old id the re-key renamed to the current indicator, saying so" do
      ksi_iam_02.update!(control_id: "ksi-iam-elp", label: "KSI-IAM-ELP")

      get indicator_api_v1_ksi_catalog_path(id: "KSI-IAM-02"), headers: auth_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data).to include("control_id" => "ksi-iam-elp", "resolved_from" => "ksi-iam-02")
    end

    it "does not add resolved_from when the id is found directly" do
      get indicator_api_v1_ksi_catalog_path(id: "ksi-iam-01"), headers: auth_headers

      expect(JSON.parse(response.body)["data"]).not_to have_key("resolved_from")
    end

    it "still 404s an old id that was retired rather than renamed, when its row is gone" do
      get indicator_api_v1_ksi_catalog_path(id: "ksi-auth-04"), headers: auth_headers

      expect(response).to have_http_status(:not_found)
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

  # #1115 — retired entries are kept, and excluded from the current catalog.
  describe "retired entries" do
    let!(:theme_auth) { create(:control_family, control_catalog: ksi_catalog, code: "AUTH", name: "Authorization by FedRAMP", sort_order: 3, retired_at: 1.day.ago) }
    let!(:retired) do
      create(:catalog_control, control_family: theme_iam, control_id: "ksi-iam-03", title: "Centralized Identity",
        retired_at: 1.day.ago, superseded_by: [ "KSI-IAM-APM" ])
    end

    it "are left out of the indicator list by default" do
      get indicators_api_v1_ksi_catalog_path, headers: auth_headers

      ids = JSON.parse(response.body)["data"].map { |d| d["control_id"] }
      expect(ids).to contain_exactly("ksi-iam-01", "ksi-iam-02", "ksi-mla-01")
    end

    it "are listed, with their successor, when include_retired=true" do
      get indicators_api_v1_ksi_catalog_path, params: { include_retired: "true" }, headers: auth_headers

      row = JSON.parse(response.body)["data"].find { |d| d["control_id"] == "ksi-iam-03" }
      expect(row["retired_at"]).to be_present
      expect(row["superseded_by"]).to eq([ "KSI-IAM-APM" ])
    end

    it "leave retired themes out of the theme list, and out of a theme's count" do
      get themes_api_v1_ksi_catalog_path, headers: auth_headers

      data = JSON.parse(response.body)["data"]
      expect(data.map { |t| t["code"] }).to eq(%w[IAM MLA])
      expect(data.first["indicators_count"]).to eq(2)
    end

    # #1193 — retired entries list after current ones, whatever sort_order they kept.
    it "orders a retired theme after the current ones with include_retired=true" do
      theme_auth.update!(sort_order: 0)

      get themes_api_v1_ksi_catalog_path, params: { include_retired: "true" }, headers: auth_headers

      expect(JSON.parse(response.body)["data"].map { |t| t["code"] }).to eq(%w[IAM MLA AUTH])
    end

    it "orders retired indicators after current ones with include_retired=true" do
      theme_auth.update!(sort_order: 0)
      create(:catalog_control, control_family: theme_auth, control_id: "ksi-auth-01", title: "Gone",
             retired_at: 1.day.ago)

      get indicators_api_v1_ksi_catalog_path, params: { include_retired: "true" }, headers: auth_headers

      # Grouped by theme: a retired indicator last within its theme, a retired
      # theme after every current one.
      ids = JSON.parse(response.body)["data"].map { |d| d["control_id"] }
      expect(ids).to eq(%w[ksi-iam-01 ksi-iam-02 ksi-iam-03 ksi-mla-01 ksi-auth-01])
    end

    it "still resolve by id, so an old reference finds what it was" do
      get indicator_api_v1_ksi_catalog_path(id: "ksi-iam-03"), headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["superseded_by"]).to eq([ "KSI-IAM-APM" ])
    end
  end

  # #1172 — the import is a user function, so it has an API surface.
  describe "POST /api/v1/ksi_catalog/import" do
    it "re-keys the catalog onto FedRAMP's snapshot" do
      post import_api_v1_ksi_catalog_path, headers: auth_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data).to include("status" => "imported", "upstream_version" => "2026.09.13.02", "dry_run" => false)
      expect(ksi_catalog.reload.version).to eq("2026.09.13.02")
      expect(ksi_iam_02.reload.control_id).to eq("ksi-iam-elp")
    end

    it "dry_run=true reports the changes and writes nothing" do
      post import_api_v1_ksi_catalog_path, params: { dry_run: "true" }, headers: auth_headers

      data = JSON.parse(response.body)["data"]
      expect(data).to include("status" => "planned", "dry_run" => true)
      expect(data["changes"]["renamed"]).to eq(1)
      expect(ksi_catalog.reload.version).to eq("1.0.0")
      expect(ksi_iam_02.reload.control_id).to eq("ksi-iam-02")
    end

    it "is unchanged the second time" do
      post import_api_v1_ksi_catalog_path, headers: auth_headers
      post import_api_v1_ksi_catalog_path, headers: auth_headers

      expect(JSON.parse(response.body)["data"]["status"]).to eq("unchanged")
    end

    it "answers 422 with the reasons when the import is refused" do
      refused = FedrampKsiImportService::Result.new(status: :refused, version: "x", changes: {}, errors: [ "/KSI: missing" ])
      allow(FedrampKsiImportService).to receive(:new).and_return(instance_double(FedrampKsiImportService, call: refused))

      post import_api_v1_ksi_catalog_path, headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["data"]).to include("status" => "refused", "errors" => [ "/KSI: missing" ])
    end

    it "works on an instance with no KSI catalog yet" do
      ksi_catalog.control_families.each { |f| f.catalog_controls.delete_all }
      ksi_catalog.control_families.delete_all
      ksi_catalog.delete

      post import_api_v1_ksi_catalog_path, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(ControlCatalog.find_by(source: "FedRAMP 20x").version).to eq("2026.09.13.02")
    end

    it "is allowed to a non-admin holding catalogs.write" do
      role = create(:role, name: "catalog_writer", scope: "instance", permissions: { "catalogs.write" => true })
      writer = create(:user)
      create(:user_role, user: writer, role: role)
      token = ApiToken.generate!(user: writer, name: "Writer")

      post import_api_v1_ksi_catalog_path, headers: { "Authorization" => "Bearer #{token.plaintext_token}" }

      expect(response).to have_http_status(:ok)
    end

    it "is refused without catalogs.write, and writes nothing" do
      reader = create(:user)
      token = ApiToken.generate!(user: reader, name: "Reader")

      post import_api_v1_ksi_catalog_path, headers: { "Authorization" => "Bearer #{token.plaintext_token}" }

      expect(response).to have_http_status(:forbidden)
      expect(ksi_catalog.reload.version).to eq("1.0.0")
    end

    it "refuses a body carrying a field it does not accept, and imports nothing" do
      post import_api_v1_ksi_catalog_path, params: { a_field: "x" }.to_json,
                                           headers: auth_headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("details" => [ "Unrecognized field: a_field" ], "expected" => [ "dry_run" ])
      expect(ksi_catalog.reload.version).to eq("1.0.0")
    end

    it "accepts dry_run in a JSON body as well as the query string" do
      post import_api_v1_ksi_catalog_path, params: { dry_run: true }.to_json,
                                           headers: auth_headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["status"]).to eq("planned")
    end

    it "is refused without a token" do
      post import_api_v1_ksi_catalog_path

      expect(response).to have_http_status(:unauthorized)
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
