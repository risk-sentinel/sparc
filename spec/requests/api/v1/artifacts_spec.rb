# frozen_string_literal: true

require "rails_helper"

# Issue #680 Phase 1 — durable artifact resolver (API). GET
# /api/v1/artifacts/:uuid resolves an immutable evidence UUID to a freshly-signed
# download URL for programmatic consumers. Token-authenticated.
RSpec.describe "Api::V1::Artifacts", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def evidence_with_file(**attrs)
    create(:evidence, **attrs).tap do |e|
      e.file.attach(io: StringIO.new("PDF-BYTES"), filename: "policy.pdf", content_type: "application/pdf")
    end
  end

  describe "authentication" do
    it "returns 401 without a token" do
      evidence = evidence_with_file
      get api_v1_artifact_path(uuid: evidence.uuid)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/artifacts/:uuid" do
    it "returns the resolved artifact with a signed URL" do
      evidence = evidence_with_file(title: "SOC 2 Report")
      get api_v1_artifact_path(uuid: evidence.uuid), headers: admin_headers
      expect(response).to have_http_status(:ok)

      data = JSON.parse(response.body)["data"]
      expect(data["uuid"]).to eq(evidence.uuid)
      expect(data["title"]).to eq("SOC 2 Report")
      expect(data["media_type"]).to eq("application/pdf")
      expect(data["url"]).to be_present
      expect(data["url"]).to include("/rails/active_storage")
    end

    it "404s for an unknown (but well-formed) UUID" do
      get api_v1_artifact_path(uuid: SecureRandom.uuid), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end

    it "404s when the artifact has no attached file" do
      evidence = create(:evidence)
      get api_v1_artifact_path(uuid: evidence.uuid), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
