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
      e.compute_file_hash! # mints the initial artifact version (#680)
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

    it "includes the current content-version UUID" do
      evidence = evidence_with_file
      get api_v1_artifact_path(uuid: evidence.uuid), headers: admin_headers
      data = JSON.parse(response.body)["data"]
      expect(data["current_version_uuid"]).to eq(evidence.current_artifact_version.uuid)
    end
  end

  describe "GET /api/v1/artifacts/versions/:uuid" do
    it "resolves a specific version with content + drift metadata" do
      evidence = evidence_with_file
      version  = evidence.current_artifact_version

      get api_v1_artifact_version_path(uuid: version.uuid), headers: admin_headers
      expect(response).to have_http_status(:ok)

      data = JSON.parse(response.body)["data"]
      expect(data["version_uuid"]).to eq(version.uuid)
      expect(data["logical_id"]).to eq(evidence.uuid) # stable identity, for drift matching
      expect(data["current"]).to be(true)
      expect(data["url"]).to include("/rails/active_storage")
    end

    it "404s for an unknown version uuid" do
      get api_v1_artifact_version_path(uuid: SecureRandom.uuid), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  # #685 — artifact review-cadence enablement (read API over the version history).
  describe "GET /api/v1/artifacts/:uuid/versions (#685)" do
    it "returns the version timeline with the delta between consecutive reviews" do
      evidence = evidence_with_file
      # compute_file_hash! mints its own version(s); reset their review dates and
      # add two with a known 60-day gap so the delta is deterministic.
      evidence.artifact_versions.update_all(reviewed_at: nil)
      evidence.artifact_versions.create!(fingerprint: "rev-a", reviewed_at: 90.days.ago)
      evidence.artifact_versions.create!(fingerprint: "rev-b", reviewed_at: 30.days.ago)

      get api_v1_artifact_version_history_path(uuid: evidence.uuid), headers: admin_headers
      expect(response).to have_http_status(:ok)

      versions = JSON.parse(response.body)["data"]["versions"]
      deltas = versions.map { |v| v["review_delta_days"] }.compact
      expect(deltas).to include(be_within(1).of(60)) # 90d ago -> 30d ago
    end

    it "requires a token" do
      evidence = evidence_with_file
      get api_v1_artifact_version_history_path(uuid: evidence.uuid)
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for an unknown uuid" do
      get api_v1_artifact_version_history_path(uuid: SecureRandom.uuid), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/artifacts/:uuid/freshness (#685)" do
    it "computes next-due + overdue from the attestation cadence" do
      evidence = evidence_with_file
      # Freshness keys off the LATEST review, so age every version.
      evidence.artifact_versions.update_all(reviewed_at: 120.days.ago)
      create(:attestation, evidence: evidence, frequency: "quarterly", status: "passed")

      get api_v1_artifact_freshness_path(uuid: evidence.uuid), headers: admin_headers
      expect(response).to have_http_status(:ok)

      data = JSON.parse(response.body)["data"]
      expect(data["review_frequency"]).to eq("quarterly")
      expect(data["last_reviewed_at"]).to be_present
      expect(data["overdue"]).to be(true)          # 120d ago + 90d cadence -> 30d overdue
      expect(data["days_overdue"]).to be >= 29
    end

    it "is not overdue when there is no fixed cadence" do
      evidence = evidence_with_file
      get api_v1_artifact_freshness_path(uuid: evidence.uuid), headers: admin_headers
      data = JSON.parse(response.body)["data"]
      expect(data["review_frequency"]).to be_nil
      expect(data["next_review_due"]).to be_nil
      expect(data["overdue"]).to be(false)
    end

    it "404s for an unknown uuid" do
      get api_v1_artifact_freshness_path(uuid: SecureRandom.uuid), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
