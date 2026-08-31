# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Attestations", type: :request do
  # #947 — declare the auth posture rather than inherit it from the developer's
  # `.env`. The roster check short-circuits with no auth enabled, so in CI
  # (which configures none) these rejection specs asserted nothing and still
  # reported green. Same convention as controller_authorization_919_spec.rb.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:user) { create(:user) }
  let(:evidence) { create(:evidence) }

  # #919 — attesting is a write on the assessor trail, so it now requires

  # evidence.write on the evidence's boundary. Granting the key rather than

  # using an admin keeps the spec honest: admin? bypasses has_permission?, so an

  # admin would stay green even if the guard were removed.

  before do
    grant_permission(user, "evidence.write", authorization_boundary: evidence.authorization_boundary)

    sign_in_as(user)
  end
  describe "GET /evidences/:evidence_id/attestations/new" do
    it "renders the new attestation form" do
      get new_evidence_attestation_path(evidence)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /evidences/:evidence_id/attestations" do
    # #947 — an attestation now references an ACCOUNT and a role that account
    # actually holds on the evidence's boundary. The name is snapshotted by the
    # server, so it is deliberately absent from the payload.
    let!(:attesting_role) do
      role = create(:role, :authorization_boundary_scoped,
                    name: "isso", display_name: "ISSO",
                    permissions: { "evidence.attest" => true })
      create(:user_role, user: attester, role: role,
             authorization_boundary: create(:authorization_boundary))
      role
    end

    let(:attester) { create(:user, display_name: "Jane Assessor") }

    def post_attestation(overrides = {})
      post evidence_attestations_path(evidence), params: {
        attestation: {
          attester_user_id: attester.id,
          role: "isso",
          statement: "This evidence is accurate and complete.",
          attested_at: Time.current.iso8601
        }.merge(overrides)
      }
    end

    it "creates an attestation with valid params" do
      expect { post_attestation }.to change(Attestation, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "snapshots the attester name from the account" do
      post_attestation
      expect(Attestation.last.attester_name).to eq("Jane Assessor")
    end

    # This assertion used to be `be_in(%w[attested draft collected reviewed])`,
    # which every possible status satisfies — it could not fail. Attesting
    # evidence marks it attested, so that is what it now checks.
    it "marks the evidence attested" do
      post_attestation
      expect(evidence.reload.status).to eq("attested")
    end

    it "generates a signature hash" do
      post_attestation
      expect(Attestation.last.signature_hash).to be_present
    end

    it "refuses an attester who holds no attesting role" do
      outsider = create(:user)

      expect { post_attestation(attester_user_id: outsider.id) }
        .not_to change(Attestation, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    # The free-text field #947 removed must not come back through the params.
    it "ignores a client-supplied attester name" do
      post_attestation(attester_name: "Someone Else")
      expect(Attestation.last.attester_name).to eq("Jane Assessor")
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
