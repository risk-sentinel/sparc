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
    # #947 — the API contract changed with the model: an attestation references
    # an ACCOUNT and a role that account actually holds on the boundary, and the
    # name is snapshotted server-side rather than supplied. So the payload names
    # `attester_user_id`, and the grant has to exist for the create to succeed.
    let(:boundary) { create(:authorization_boundary) }
    let(:evidence) { create(:evidence, authorization_boundary: boundary) }
    let(:attester) { create(:user, display_name: "API Reviewer") }

    let!(:attesting_role) do
      role = create(:role, :authorization_boundary_scoped,
                    name: "isso", display_name: "ISSO",
                    permissions: { "evidence.attest" => true })
      create(:user_role, user: attester, role: role, authorization_boundary: boundary)
      role
    end

    let(:valid_params) do
      {
        attestation: {
          attester_user_id: attester.id,
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
      expect(parsed.dig("data", "attester_verified")).to be(true)
    end

    # #947 — the name is a SNAPSHOT taken from the account, never client input.
    it "snapshots the attester name from the account and ignores a supplied one" do
      spoofed = valid_params.deep_merge(attestation: { attester_name: "Someone Else" })
      post api_v1_evidence_attestations_path(evidence_id: evidence.id),
           params: spoofed, headers: admin_headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("data", "attester_name")).to eq("API Reviewer")
    end

    it "rejects an attester who holds no attesting role on the boundary" do
      outsider = create(:user)
      params = valid_params.deep_merge(attestation: { attester_user_id: outsider.id })

      post api_v1_evidence_attestations_path(evidence_id: evidence.id),
           params: params, headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"].join).to match(/holds no role|does not hold/i)
    end

    it "rejects a role that does not carry evidence.attest" do
      create(:role, :authorization_boundary_scoped,
             name: "view_only", display_name: "View Only",
             permissions: { "evidence.read" => true })
      params = valid_params.deep_merge(attestation: { role: "view_only" })

      post api_v1_evidence_attestations_path(evidence_id: evidence.id),
           params: params, headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"].join).to match(/not a role that may attest/i)
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
      # #947 — the factory links one control already (evidence must support one),
      # so the two asserted here are named rather than added on top of it.
      evidence.evidence_control_links.destroy_all
      evidence.evidence_control_links.create!(control_id: "AC-2")
      evidence.evidence_control_links.create!(control_id: "AC-3")
      jane = create(:user, display_name: "Jane")
      ciso = create(:role, :authorization_boundary_scoped,
                    name: "ciso", display_name: "CISO",
                    permissions: { "evidence.attest" => true })
      # This evidence is instance-wide (no boundary), so eligibility falls back
      # to "may attest on some boundary" — the grant lives on one of its own.
      create(:user_role, user: jane, role: ciso,
             authorization_boundary: create(:authorization_boundary))

      create(:attestation, evidence: evidence,
             attester_user: jane, role: "ciso",
             grant_boundary_id: nil,
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
      # The CMS shape is meaningless without a control_id. Evidence must now
      # support a control, so a link-less row is a pre-rule one — written the
      # way a pre-rule row is, by skipping the validation that forbids it.
      unlinked = build(:evidence, :without_control_links)
      unlinked.slug = "cms-export-unlinked"
      unlinked.save!(validate: false)

      create(:attestation, evidence: unlinked)
      get export_api_v1_evidence_attestations_path(evidence_id: unlinked.id),
          headers: admin_headers
      expect(JSON.parse(response.body)["data"]).to be_empty
    end

    it "keeps the linked-evidence export non-empty (the control of the above)" do
      create(:attestation, evidence: evidence)
      get export_api_v1_evidence_attestations_path(evidence_id: evidence.id),
          headers: admin_headers
      expect(JSON.parse(response.body)["data"]).not_to be_empty
    end
  end
end
