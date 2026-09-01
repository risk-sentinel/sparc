# frozen_string_literal: true

require "rails_helper"

# #911 layer 2 — a document that cannot name the baseline its controls descend
# from may be read, listed and exported, but not edited.
#
# The rule is deliberately asymmetric. Refusing reads would break every existing
# deployment overnight for no safety gain; refusing edits stops a person adding
# to a document whose control references mean nothing verifiable. Setting the
# baseline is itself the permitted write, so the gate is a prompt rather than a
# trap.
RSpec.describe "Api::V1 reconciliation gate", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:catalog) { create(:control_catalog) }
  let(:baseline) { create(:profile_document, control_catalog: catalog) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "an SSP with no imported profile" do
    # #911 — a document with no controls has nothing to trace, so the gate
    # correctly leaves it alone. These fixtures claim a control so the gate
    # applies; that behaviour is pinned in catalog_lineage_spec.
    let!(:ssp) do
      create(:ssp_document, profile_document: nil, name: "Legacy SSP").tap do |doc|
        create(:ssp_control, ssp_document: doc, control_id: "ac-1")
      end
    end

    it "can still be read" do
      get api_v1_ssp_document_path(ssp), headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "can still be listed" do
      get api_v1_ssp_documents_path, headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "refuses an update with 422" do
      put api_v1_ssp_document_path(ssp), params: { ssp_document: { name: "Edited" } },
          headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(ssp.reload.name).to eq("Legacy SSP"), "the refused write must not partially apply"
    end

    # The refusal body is the SAME object the document reports when advisory,
    # so an integrator writes one handler and reads `blocking` to tell them
    # apart rather than learning a second shape on first refusal.
    it "returns the reconciliation object, carrying the remedy" do
      put api_v1_ssp_document_path(ssp), params: { ssp_document: { name: "Edited" } },
          headers: auth_headers, as: :json

      reconciliation = JSON.parse(response.body)["reconciliation"]
      expect(reconciliation["status"]).to eq("unresolved")
      expect(reconciliation["blocking"]).to eq([ "update" ])

      issue = reconciliation["issues"].first
      expect(issue["code"]).to eq("missing_profile_source")
      # `remedy` is prose for the screen; `options` is the machine-readable half
      # an integrator uses. Both travel in the 422 body — only `remedy` is ever
      # rendered, which is why it must not be an endpoint.
      expect(issue["remedy"]).to eq("Choose the profile whose baseline these controls were selected from.")
      expect(issue["remedy"]).not_to match(%r{/api/})
      expect(issue["options"]).to eq("/api/v1/profile_documents")
    end

    it "names the remedy in the human-readable error too" do
      put api_v1_ssp_document_path(ssp), params: { ssp_document: { name: "Edited" } },
          headers: auth_headers, as: :json

      expect(JSON.parse(response.body)["error"]).to include("Choose the profile")
    end

    # The exit. Without this the gate would make an unresolved document
    # permanently uneditable, since declaring the baseline IS an update.
    it "permits the write that declares the baseline" do
      put api_v1_ssp_document_path(ssp),
          params: { ssp_document: { profile_document_id: baseline.id } },
          headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(ssp.reload.profile_document).to eq(baseline)
    end

    it "permits an ordinary edit once the baseline is declared" do
      ssp.update!(profile_document: baseline)

      put api_v1_ssp_document_path(ssp), params: { ssp_document: { name: "Edited" } },
          headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(ssp.reload.name).to eq("Edited")
    end

    # A caller must not be able to slip an unrelated edit past the gate by
    # sending an empty baseline. Clearing the FK is not reconciling.
    it "does not accept a blank baseline as reconciliation" do
      put api_v1_ssp_document_path(ssp),
          params: { ssp_document: { name: "Edited", profile_document_id: "" } },
          headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(ssp.reload.name).to eq("Legacy SSP")
    end
  end

  # Reading is never refused, so an operator can always see what needs fixing
  # before being stopped by it.
  describe "a resolved document" do
    it "updates normally" do
      ssp = create(:ssp_document, profile_document: baseline, name: "Current")

      put api_v1_ssp_document_path(ssp), params: { ssp_document: { name: "Edited" } },
          headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(ssp.reload.name).to eq("Edited")
    end
  end

  # Deleting an unreconciled document must stay possible — otherwise a
  # deployment's way out of bad legacy data would be blocked by the very gate
  # meant to improve it.
  describe "destroy" do
    it "is not blocked by the gate" do
      ssp = create(:ssp_document, profile_document: nil)

      delete api_v1_ssp_document_path(ssp), headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end
end
