# frozen_string_literal: true

require "rails_helper"

# #832 — the API must reject an incomplete POA&M risk with a 422 that NAMES the
# missing fields, at the point of entry. Before this, the record was accepted
# and the failure surfaced much later as a POA&M that would not pass OSCAL
# schema validation at export, with nothing to indicate which record caused it.
RSpec.describe "Api::V1::PoamRisks", type: :request do
  # Without this, `authenticate_api_token!` takes its "no auth configured"
  # branch and grants anonymous access, so the authorization examples below
  # would pass for the wrong reason (or blow up on a nil current_user).
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:document) { create(:poam_document, authorization_boundary: boundary) }
  let(:admin) { create(:user, :admin) }
  let(:token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  let(:complete_attrs) do
    {
      title: "Hard-coded credentials in the admin panel",
      description: "Static credentials are present in the deployed configuration.",
      statement: "An attacker with read access to the image can authenticate as an administrator.",
      status: "open",
      deadline: 30.days.from_now.iso8601
    }
  end

  describe "POST /api/v1/poam_documents/:id/risks" do
    it "creates a complete risk" do
      post "/api/v1/poam_documents/#{document.id}/risks",
           params: { poam_risk: complete_attrs }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("data", "title")).to eq(complete_attrs[:title])
      expect(body.dig("data", "uuid")).to be_present
      expect(body["data"]).not_to have_key("missing_fields")
      expect(document.poam_risks.count).to eq(1)
    end

    # The heart of #832. Each field on its own, so an over-broad rejection
    # cannot satisfy this by refusing everything.
    %i[title description statement status deadline].each do |field|
      it "rejects a risk with no #{field} and names it" do
        post "/api/v1/poam_documents/#{document.id}/risks",
             params: { poam_risk: complete_attrs.except(field) }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        details = JSON.parse(response.body)["details"].to_s
        expect(details).to match(/#{field.to_s.humanize}/i),
          "422 did not name the missing field #{field}: #{response.body}"
        expect(document.poam_risks.count).to eq(0),
          "an invalid risk was persisted anyway — the failure would resurface at export"
      end
    end
  end

  describe "PATCH /api/v1/poam_risks/:id" do
    let!(:risk) { create(:poam_risk, poam_document: document) }

    it "updates a risk" do
      patch "/api/v1/poam_risks/#{risk.id}",
            params: { poam_risk: { title: "Revised title" } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(risk.reload.title).to eq("Revised title")
    end

    it "refuses to blank a required field" do
      patch "/api/v1/poam_risks/#{risk.id}",
            params: { poam_risk: { deadline: nil } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(risk.reload.deadline).to be_present
    end
  end

  describe "GET /api/v1/poam_documents/:id/risks" do
    it "flags rows written before the rules existed" do
      create(:poam_risk, poam_document: document)
      create(:poam_risk, :incomplete, poam_document: document)

      get "/api/v1/poam_documents/#{document.id}/risks", headers: headers

      expect(response).to have_http_status(:ok)
      flagged = JSON.parse(response.body)["data"].filter_map { |r| r["missing_fields"] }
      expect(flagged.size).to eq(1)
      expect(flagged.first).to contain_exactly("statement", "deadline")
    end
  end

  describe "authorization" do
    it "rejects an unauthenticated request" do
      post "/api/v1/poam_documents/#{document.id}/risks",
           params: { poam_risk: complete_attrs }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids a user without poam.write on the boundary" do
      other = create(:user)
      other_token = ApiToken.generate!(user: other, name: "Other")

      post "/api/v1/poam_documents/#{document.id}/risks",
           params: { poam_risk: complete_attrs },
           headers: { "Authorization" => "Bearer #{other_token.plaintext_token}" }, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
