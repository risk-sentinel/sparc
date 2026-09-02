# frozen_string_literal: true

require "rails_helper"

# #1090 — SAR risks had no API at all, and no way to carry a rating.
#
# POA&M has eight sub-resource controllers; SAR had none, so a risk was reachable
# only through the HTML enrich form, which permitted `title`, `description` and
# `status`. `impact` and `likelihood` — the OSCAL rating — could not be set
# anywhere, and the columns sat blank on all 17 seeded risks.
RSpec.describe "Api::V1::SarRisks", type: :request do
  # Without this, `authenticate_api_token!` takes its "no auth configured" branch
  # and grants anonymous access, so the authorization examples would pass for the
  # wrong reason.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:document) { create(:sar_document, authorization_boundary: boundary) }
  let!(:result)  { create(:sar_result, sar_document: document) }
  let(:admin)    { create(:user, :admin) }
  let(:token)    { ApiToken.generate!(user: admin, name: "Test") }
  let(:headers)  { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  let(:complete_attrs) do
    {
      title: "Unpatched TLS library in the web tier",
      description: "The deployed image carries a TLS library with a known flaw.",
      statement: "An attacker on the path could downgrade the connection.",
      status: "open",
      impact: "high",
      likelihood: "moderate"
    }
  end

  describe "POST /api/v1/sar_documents/:id/risks" do
    it "creates a risk carrying its rating" do
      post "/api/v1/sar_documents/#{document.id}/risks",
           params: { sar_risk: complete_attrs }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["impact"]).to eq("high")
      expect(data["likelihood"]).to eq("moderate")
      expect(data["uuid"]).to be_present
      expect(data).not_to have_key("missing_fields")
    end

    it "reports the rating as the FACETS it will export as" do
      post "/api/v1/sar_documents/#{document.id}/risks",
           params: { sar_risk: complete_attrs }, headers: headers, as: :json

      chars = JSON.parse(response.body).dig("data", "characterizations")
      facets = chars.flat_map { |c| c["facets"] }
      # name/system/value are all REQUIRED on a facet by the OSCAL schema.
      expect(facets).to all(include("name", "system", "value"))
      expect(facets.map { |f| [ f["name"], f["value"] ] })
        .to contain_exactly([ "impact", "high" ], [ "likelihood", "moderate" ])
    end

    it "rejects an incomplete risk with a 422 that NAMES the gaps" do
      post "/api/v1/sar_documents/#{document.id}/risks",
           params: { sar_risk: { title: "Only a title" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/statement|description|status/i)
    end

    it "refuses a field the endpoint does not accept, rather than ignoring it" do
      post "/api/v1/sar_documents/#{document.id}/risks",
           params: { sar_risk: complete_attrs.merge(not_a_field: "x") },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:bad_request)
    end
  end

  describe "PATCH /api/v1/sar_risks/:id" do
    let(:risk) { create(:sar_risk, sar_result: result, impact: nil, likelihood: nil) }

    it "sets a rating on a risk that had none" do
      patch "/api/v1/sar_risks/#{risk.id}",
            params: { sar_risk: { impact: "very-high", likelihood: "low" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(risk.reload.impact).to eq("very-high")
      expect(risk.likelihood).to eq("low")
    end
  end

  describe "GET /api/v1/sar_documents/:id/risks" do
    it "lists the document's risks" do
      create(:sar_risk, sar_result: result, title: "Listed risk")

      get "/api/v1/sar_documents/#{document.id}/risks", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].map { |r| r["title"] }).to include("Listed risk")
      # The API-wide collection envelope: page/pages/count/items (base_controller
      # #paginate). Asserted by name so a change to the envelope is caught here
      # rather than by a consumer.
      expect(body["meta"]).to include("page", "pages", "count", "items")
    end

    it "accepts the slug the document listing hands out, not only the id" do
      get "/api/v1/sar_documents/#{document.slug}/risks", headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "authorization" do
    it "rejects an unauthenticated request" do
      get "/api/v1/sar_documents/#{document.id}/risks"

      expect(response).to have_http_status(:unauthorized)
    end

    # BOTH directions, and the allow leg uses a NON-admin holding the permission:
    # `admin?` short-circuits `has_permission?` entirely, so an admin-only test
    # would pass without exercising the guard at all.
    context "a non-admin holding sar.write on the boundary" do
      let(:writer) { grant_permission(create(:user), "sar.write", authorization_boundary: boundary) }
      let(:writer_headers) do
        { "Authorization" => "Bearer #{ApiToken.generate!(user: writer, name: 'W').plaintext_token}" }
      end

      before { grant_permission(writer, "sar.read", authorization_boundary: boundary) }

      it "is allowed to create" do
        post "/api/v1/sar_documents/#{document.id}/risks",
             params: { sar_risk: complete_attrs }, headers: writer_headers, as: :json

        expect(response).to have_http_status(:created)
      end
    end

    context "a non-admin holding no SAR permission" do
      let(:outsider) { create(:user) }
      let(:outsider_headers) do
        { "Authorization" => "Bearer #{ApiToken.generate!(user: outsider, name: 'O').plaintext_token}" }
      end

      it "is refused a read" do
        get "/api/v1/sar_documents/#{document.id}/risks", headers: outsider_headers

        expect(response).to have_http_status(:forbidden)
      end

      it "is refused a write" do
        post "/api/v1/sar_documents/#{document.id}/risks",
             params: { sar_risk: complete_attrs }, headers: outsider_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
