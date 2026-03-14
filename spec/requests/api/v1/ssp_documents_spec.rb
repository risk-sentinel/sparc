# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SspDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /api/v1/ssp_documents/:id/export" do
    it "returns JSON export of the document" do
      ssp = create(:ssp_document)
      get export_api_v1_ssp_document_path(ssp)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "PUT /api/v1/ssp_documents/:id/update_fields" do
    it "updates control fields" do
      ssp = create(:ssp_document)
      control = create(:ssp_control, ssp_document: ssp, control_id: "ac-1")
      create(:ssp_control_field, ssp_control: control, field_name: "status", field_value: "draft", editable: true)

      put update_fields_api_v1_ssp_document_path(ssp), params: {
        controls: { "ac-1" => { "status" => "implemented" } }
      }, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["success"]).to be true
    end
  end

  describe "POST /api/v1/ssp_documents/convert" do
    it "rejects request without file" do
      post convert_api_v1_ssp_documents_path, as: :json
      expect(response).to have_http_status(:bad_request)
      parsed = JSON.parse(response.body)
      expect(parsed["error"]).to include("No file provided")
    end
  end
end
