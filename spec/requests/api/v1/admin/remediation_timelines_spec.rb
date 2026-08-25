# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Admin::RemediationTimelines", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET /api/v1/admin/remediation_timelines" do
    it "returns the full baseline x criticality grid for an admin" do
      get "/api/v1/admin/remediation_timelines", headers: admin_headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.length).to eq(RemediationTimeline::BASELINE_LEVELS.size * RemediationTimeline::CRITICALITIES.size)
      cell = data.find { |c| c["baseline_level"] == "Moderate" && c["criticality"] == "High" }
      expect(cell["days"]).to eq(30) # built-in default when unprovisioned
    end

    it "forbids a non-admin" do
      get "/api/v1/admin/remediation_timelines", headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "401 without a token" do
      get "/api/v1/admin/remediation_timelines"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/admin/remediation_timelines" do
    it "upserts a cell" do
      put "/api/v1/admin/remediation_timelines",
          params: { baseline_level: "High", criticality: "Critical", days: 3 }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(RemediationTimeline.find_by(baseline_level: "High", criticality: "Critical").days).to eq(3)
    end

    it "422 on an invalid cell" do
      put "/api/v1/admin/remediation_timelines",
          params: { baseline_level: "Nope", criticality: "Critical", days: 3 }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
