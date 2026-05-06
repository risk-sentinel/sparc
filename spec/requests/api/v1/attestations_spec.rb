# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Attestations", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }
  let(:evidence)      { create(:evidence) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_evidence_attestations_path(evidence_id: evidence.id)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/evidences/:evidence_id/attestations" do
    it "returns paginated list for admin" do
      create_list(:attestation, 2, evidence: evidence)
      get api_v1_evidence_attestations_path(evidence_id: evidence.id), headers: admin_headers
      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "accepts evidence slug as the route key" do
      create(:attestation, evidence: evidence)
      get api_v1_evidence_attestations_path(evidence_id: evidence.slug), headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it "404s for unknown evidence" do
      get api_v1_evidence_attestations_path(evidence_id: 999_999), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/evidences/:evidence_id/attestations/:id" do
    it "returns the detailed shape" do
      attestation = create(:attestation, evidence: evidence, frequency: "annually")
      get api_v1_evidence_attestation_path(evidence_id: evidence.id, id: attestation.id),
          headers: admin_headers
      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]).to include("statement", "signature_hash", "frequency_label")
      expect(parsed["data"]["frequency"]).to eq("annually")
    end
  end

  describe "POST /api/v1/evidences/:evidence_id/attestations" do
    let(:valid_params) do
      {
        attestation: {
          attester_name: "API Reviewer",
          attester_email: "api@example.com",
          role: "isso",
          statement: "Verified via API.",
          attested_at: Time.current.iso8601,
          frequency: "annually",
          status: "passed"
        }
      }
    end

    it "creates and signs the attestation" do
      post api_v1_evidence_attestations_path(evidence_id: evidence.id),
           params: valid_params, headers: admin_headers
      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed.dig("data", "signature_hash")).to be_present
      expect(parsed.dig("data", "frequency")).to eq("annually")
    end

    it "rejects an invalid frequency" do
      bad = valid_params.deep_merge(attestation: { frequency: "fortnightly" })
      post api_v1_evidence_attestations_path(evidence_id: evidence.id),
           params: bad, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"]).to include(/Frequency/i)
    end

    it "audits the creation" do
      expect {
        post api_v1_evidence_attestations_path(evidence_id: evidence.id),
             params: valid_params, headers: admin_headers
      }.to change { AuditEvent.where(action: "attestation_created").count }.by(1)
    end
  end

  describe "DELETE /api/v1/evidences/:evidence_id/attestations/:id" do
    it "destroys and audits" do
      attestation = create(:attestation, evidence: evidence)
      expect {
        delete api_v1_evidence_attestation_path(evidence_id: evidence.id, id: attestation.id),
               headers: admin_headers
      }.to change(Attestation, :count).by(-1)
        .and change { AuditEvent.where(action: "attestation_deleted").count }.by(1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /api/v1/evidences/:evidence_id/attestations/export" do
    it "emits CMS-shape JSON denormalized per linked control" do
      evidence.evidence_control_links.create!(control_id: "AC-2")
      evidence.evidence_control_links.create!(control_id: "AC-3")
      create(:attestation, evidence: evidence,
             attester_name: "Jane", role: "ciso",
             statement: "Verified.",
             attested_at: Time.utc(2026, 4, 1, 12, 0, 0),
             frequency: "annually", status: "passed")

      get export_api_v1_evidence_attestations_path(evidence_id: evidence.id),
          headers: admin_headers
      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["meta"]).to include("count" => 2, "schema" => "cms-attestation-v1")
      expect(parsed["data"].length).to eq(2)
      expect(parsed["data"].first).to include(
        "control_id" => "AC-2",
        "explanation" => "Verified.",
        "frequency" => "annually",
        "status" => "passed",
        "updated" => "2026-04-01T12:00:00Z",
        "updated_by" => "Jane (CISO)"
      )
    end

    it "returns an empty array when evidence has no control links" do
      create(:attestation, evidence: evidence)
      get export_api_v1_evidence_attestations_path(evidence_id: evidence.id),
          headers: admin_headers
      expect(JSON.parse(response.body)["data"]).to be_empty
    end
  end
end
