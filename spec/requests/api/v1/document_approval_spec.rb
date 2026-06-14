# frozen_string_literal: true

require "rails_helper"

# #630 — API review/approval endpoints (catalog/profile/cdef) + #633 baseline review.
RSpec.describe "Api::V1 document approval", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:admin_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'Admin').plaintext_token}" } }
  let(:regular) { create(:user) }
  let(:regular_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: regular, name: 'User').plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "Control Catalog approval" do
    let(:catalog) { create(:control_catalog) }

    it "submits for review (admin)" do
      post submit_for_review_api_v1_control_catalog_path(catalog), headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["approval_status"]).to eq("pending_review")
    end

    it "approves a pending catalog (admin)" do
      catalog.submit_for_review!(create(:user))
      post approve_api_v1_control_catalog_path(catalog), headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(catalog.reload.approval_status).to eq("approved")
    end

    it "returns 403 when a non-authorized user tries to approve" do
      catalog.submit_for_review!(create(:user))
      post approve_api_v1_control_catalog_path(catalog), headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(catalog.reload.approval_status).to eq("pending_review")
    end

    it "returns 403 when a non-writer tries to submit" do
      post submit_for_review_api_v1_control_catalog_path(catalog), headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "CDEF approval" do
    it "blocks submitting an empty CDEF (#634)" do
      cdef = create(:cdef_document)
      post submit_for_review_api_v1_cdef_document_path(cdef), headers: admin_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(cdef.reload.approval_status).to eq("draft")
    end
  end

  describe "GET baseline_review (#633)" do
    it "returns the selected-vs-expected baseline diff" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog)
      create(:catalog_control, control_family: family, control_id: "ac-1", baseline_impact: "MODERATE, HIGH")
      create(:catalog_control, control_family: family, control_id: "ac-2", baseline_impact: "MODERATE")
      profile = create(:profile_document, control_catalog: catalog, baseline_level: "MODERATE")
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1")

      get baseline_review_api_v1_profile_document_path(profile), headers: admin_headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["expected_count"]).to eq(2)
      expect(data["missing_controls"]).to eq([ "ac-2" ])
      expect(data["selection_matches_baseline"]).to be(false)
    end
  end
end
