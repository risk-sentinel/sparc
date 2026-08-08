# frozen_string_literal: true

require "rails_helper"

# #911 layer 2 — the instance-wide report, on both surfaces.
#
# Admin-only on purpose: it enumerates every document regardless of boundary
# membership, which is a wider view than any single author is entitled to.
RSpec.describe "Reconciliation report", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }
  let(:catalog) { create(:control_catalog) }
  let(:baseline) { create(:profile_document, control_catalog: catalog) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /api/v1/admin/reconciliation" do
    let(:admin_token) { ApiToken.generate!(user: admin, name: "Test") }
    let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

    it "reports unresolved documents with their remedy" do
      legacy = create(:ssp_document, profile_document: nil, name: "Legacy SSP")
      create(:ssp_control, ssp_document: legacy, control_id: "ac-1")

      get api_v1_admin_reconciliation_index_path, headers: admin_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["blocking"]).to eq(1)

      row = data["documents"].first
      expect(row["name"]).to eq("Legacy SSP")
      # Same object as the per-document payload and the 422 refusal body.
      expect(row["reconciliation"]["issues"].first["code"]).to eq("missing_profile_source")
      expect(row["reconciliation"]["issues"].first["remedy"]).to be_present
    end

    it "reports totals per type so a count has a denominator" do
      unresolved = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: unresolved, control_id: "ac-1")
      create(:ssp_document, profile_document: baseline)

      get api_v1_admin_reconciliation_index_path, headers: admin_headers

      entry = JSON.parse(response.body).dig("data", "by_type")
                  .find { _1["type"] == SspDocument.model_name.human.pluralize }
      expect(entry["affected"]).to eq(1)
      expect(entry["total"]).to eq(2)
    end

    it "returns an empty report when everything resolves" do
      create(:ssp_document, profile_document: baseline)

      get api_v1_admin_reconciliation_index_path, headers: admin_headers

      data = JSON.parse(response.body)["data"]
      expect(data["total"]).to eq(0)
      expect(data["documents"]).to eq([])
    end

    it "refuses a non-admin" do
      token = ApiToken.generate!(user: member, name: "Member")

      get api_v1_admin_reconciliation_index_path,
          headers: { "Authorization" => "Bearer #{token.plaintext_token}" }

      expect(response).not_to have_http_status(:ok)
    end

    it "requires a token" do
      get api_v1_admin_reconciliation_index_path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /admin/reconciliation" do
    it "lists the affected documents and what each needs" do
      sign_in_as(admin)
      legacy = create(:ssp_document, profile_document: nil, name: "Legacy SSP")
      create(:ssp_control, ssp_document: legacy, control_id: "ac-1")

      get admin_reconciliation_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Legacy SSP")
      expect(response.body).to include("Blocks edits")
      expect(response.body).to include("cannot be traced to a catalog")
    end

    it "says so plainly when nothing needs reconciliation" do
      sign_in_as(admin)
      create(:ssp_document, profile_document: baseline)

      get admin_reconciliation_index_path

      expect(response.body).to include("Every document can name its catalog")
    end

    it "is not reachable by a non-admin" do
      sign_in_as(member)

      get admin_reconciliation_index_path

      expect(response).not_to have_http_status(:ok)
    end
  end
end
