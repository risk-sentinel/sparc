# frozen_string_literal: true

require "rails_helper"

# #1025 — the `generate` endpoints accept the identifier their own listings
# return.
#
# Both resolved the source document by numeric id alone, while SSP and SAR
# documents are slug-addressed everywhere else. A caller who listed documents
# received slugs and was told the document did not exist when they passed one
# back. `find_by(id:)` against a slug raises nothing — Postgres casts the
# string, matches no row, and the 404 blames the document rather than the key.
RSpec.describe "Api::V1 generate source lookup", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" }
  end
  let(:boundary) { create(:authorization_boundary) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "POST /api/v1/sap_documents/generate" do
    # With no controls the generator refuses by design (#844: "an assessment
    # plan covering nothing is not a degraded result, it is a wrong one"), so
    # the source needs content for the lookup path to be exercised end to end.
    let!(:ssp) do
      create(:ssp_document, authorization_boundary: boundary).tap do |doc|
        create(:ssp_control, ssp_document: doc, control_id: "AC-1")
      end
    end

    it "accepts the SSP's slug — the identifier the listing returns" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: ssp.slug } },
        headers: headers, as: :json

      expect(response).to have_http_status(:created), response.body
    end

    it "still accepts the SSP's numeric id" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: ssp.id } },
        headers: headers, as: :json

      expect(response).to have_http_status(:created), response.body
    end

    it "still 404s for an identifier that matches nothing" do
      post generate_api_v1_sap_documents_path,
        params: { sap_document: { ssp_document_id: "no-such-ssp-anywhere" } },
        headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/poam_documents/generate" do
    let!(:sar) do
      create(:sar_document, authorization_boundary: boundary).tap do |doc|
        create(:sar_control, sar_document: doc, control_id: "AC-1")
      end
    end

    it "accepts the SAR's slug" do
      post generate_api_v1_poam_documents_path,
        params: { poam_document: { sar_document_id: sar.slug } },
        headers: headers, as: :json

      expect(response).to have_http_status(:created), response.body
    end

    it "still accepts the SAR's numeric id" do
      post generate_api_v1_poam_documents_path,
        params: { poam_document: { sar_document_id: sar.id } },
        headers: headers, as: :json

      expect(response).to have_http_status(:created), response.body
    end

    it "still 404s for an identifier that matches nothing" do
      post generate_api_v1_poam_documents_path,
        params: { poam_document: { sar_document_id: "no-such-sar-anywhere" } },
        headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
