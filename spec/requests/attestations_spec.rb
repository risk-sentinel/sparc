# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Attestations", type: :request do
  let(:user) { create(:user) }
  let(:evidence) { create(:evidence) }

  before { sign_in_as(user) }

  describe "GET /evidences/:evidence_id/attestations/new" do
    it "renders the new attestation form" do
      get new_evidence_attestation_path(evidence)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /evidences/:evidence_id/attestations" do
    it "creates an attestation with valid params" do
      expect {
        post evidence_attestations_path(evidence), params: {
          attestation: {
            attester_name: "Jane Assessor",
            attester_email: "jane@example.com",
            role: "assessor",
            statement: "This evidence is accurate and complete.",
            attested_at: Time.current.iso8601
          }
        }
      }.to change(Attestation, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "updates evidence status" do
      post evidence_attestations_path(evidence), params: {
        attestation: {
          attester_name: "Jane Assessor",
          attester_email: "jane@example.com",
          role: "assessor",
          statement: "This evidence is accurate.",
          attested_at: Time.current.iso8601
        }
      }
      evidence.reload
      expect(evidence.status).to be_in(%w[attested draft collected reviewed])
    end

    it "generates a signature hash" do
      post evidence_attestations_path(evidence), params: {
        attestation: {
          attester_name: "Jane Assessor",
          attester_email: "jane@example.com",
          role: "assessor",
          statement: "This evidence is accurate.",
          attested_at: Time.current.iso8601
        }
      }
      expect(Attestation.last.signature_hash).to be_present
    end
  end

  describe "DELETE /evidences/:evidence_id/attestations/:id" do
    it "deletes the attestation" do
      attestation = create(:attestation, evidence: evidence)
      expect {
        delete evidence_attestation_path(evidence, attestation)
      }.to change(Attestation, :count).by(-1)
      expect(response).to have_http_status(:redirect)
    end
  end
end
