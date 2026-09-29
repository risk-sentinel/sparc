# frozen_string_literal: true

require "rails_helper"

# #1154 — the new decision data is writable and readable through the API (the
# UI is never the only way to perform a mutation): the boundary's
# authorization_date / next_decision_date, a POA&M risk's blocks_ato /
# condition_expires / reopen_trigger, and a SAR risk's blocks_ato.
RSpec.describe "Api::V1 ATO decision fields (#1154)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:admin) { create(:user, :admin) }
  let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'Test').plaintext_token}" } }
  let(:outsider_headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: create(:user), name: 'Other').plaintext_token}" }
  end
  let(:boundary) { create(:authorization_boundary) }

  def body = JSON.parse(response.body)

  describe "authorization boundary dates" do
    it "writes both dates and reads them back on update, show and index" do
      patch "/api/v1/authorization_boundaries/#{boundary.id}",
            params: { authorization_boundary: { authorization_date: "2025-10-11", next_decision_date: "2026-10-11" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["data"]).to include("authorization_date" => "2025-10-11", "next_decision_date" => "2026-10-11")
      expect(boundary.reload.next_decision_date).to eq("2026-10-11")

      get "/api/v1/authorization_boundaries/#{boundary.slug}", headers: headers
      expect(body["data"]).to include("authorization_date" => "2025-10-11", "next_decision_date" => "2026-10-11")
    end

    it "accepts the dates on create" do
      post "/api/v1/authorization_boundaries",
           params: { authorization_boundary: { name: "Dated", next_decision_date: "2027-01-31" } },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(AuthorizationBoundary.find(body.dig("data", "id")).next_decision_date).to eq("2027-01-31")
    end

    it "refuses a date that is not YYYY-MM-DD with a 422 and stores nothing" do
      patch "/api/v1/authorization_boundaries/#{boundary.id}",
            params: { authorization_boundary: { next_decision_date: "11/10/2026" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(boundary.reload.next_decision_date).to be_nil
    end

    it "forbids a user without authorization_boundaries.write" do
      patch "/api/v1/authorization_boundaries/#{boundary.id}",
            params: { authorization_boundary: { next_decision_date: "2026-10-11" } },
            headers: outsider_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(boundary.reload.next_decision_date).to be_nil
    end
  end

  describe "POA&M risk decision fields" do
    let(:document) { create(:poam_document, authorization_boundary: boundary) }
    let(:risk) { create(:poam_risk, poam_document: document) }
    let(:decision) { { blocks_ato: true, condition_expires: "2026-11-01", reopen_trigger: "score<0.85" } }

    it "writes and reads back all three" do
      patch "/api/v1/poam_risks/#{risk.id}", params: { poam_risk: decision }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["data"]).to include("blocks_ato" => true, "condition_expires" => "2026-11-01",
                                      "reopen_trigger" => "score<0.85")

      get "/api/v1/poam_documents/#{document.id}/risks", headers: headers
      expect(body["data"].first).to include("blocks_ato" => true)
    end

    it "clears blocks_ato back to undecided with null" do
      risk.update!(blocks_ato: false)
      patch "/api/v1/poam_risks/#{risk.id}", params: { poam_risk: { blocks_ato: nil } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(risk.reload.blocks_ato).to be_nil
    end

    {
      blocks_ato: "maybe", condition_expires: "2026-13-40", reopen_trigger: "score=0.85"
    }.each do |field, bad|
      it "refuses #{field}=#{bad.inspect} with a 422 naming the field" do
        patch "/api/v1/poam_risks/#{risk.id}", params: { poam_risk: { field => bad } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to match(/#{field.to_s.humanize}/i)
        expect(risk.reload.public_send(field)).to be_nil
      end
    end

    it "forbids a user without poam.write" do
      patch "/api/v1/poam_risks/#{risk.id}", params: { poam_risk: decision }, headers: outsider_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(risk.reload.blocks_ato).to be_nil
    end
  end

  describe "SAR risk blocks_ato" do
    let(:sar) { create(:sar_document, authorization_boundary: boundary) }
    let(:risk) { create(:sar_risk, sar_result: create(:sar_result, sar_document: sar)) }

    it "writes and reads back blocks_ato" do
      patch "/api/v1/sar_risks/#{risk.id}", params: { sar_risk: { blocks_ato: false } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["data"]).to include("blocks_ato" => false)
      expect(risk.reload.blocks_ato).to be(false)
    end

    it "does not accept the POA&M-only decision conditions" do
      patch "/api/v1/sar_risks/#{risk.id}", params: { sar_risk: { reopen_trigger: "score<0.85" } },
                                            headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "forbids a user without sar.write" do
      patch "/api/v1/sar_risks/#{risk.id}", params: { sar_risk: { blocks_ato: true } }, headers: outsider_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(risk.reload.blocks_ato).to be_nil
    end
  end
end
