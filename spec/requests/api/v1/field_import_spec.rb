# frozen_string_literal: true

require "rails_helper"

# #716 — bulk editable-field file import (preview → confirm) for the downstream
# document types. Covers both authorization styles: SSP (DocumentBaseController
# document.write) and CDEF (converters.write, like bulk-apply).
RSpec.describe "Api::V1 field import", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def upload(hash, name: "fields.json")
    file = Tempfile.new([ "fields", ".json" ])
    file.write(hash.is_a?(String) ? hash : hash.to_json)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: name)
  end

  describe "SSP (document.write authz)" do
    let(:document) { create(:ssp_document) }
    let!(:control) { create(:ssp_control, ssp_document: document, control_id: "AC-1") }
    let(:body) { { "controls" => { "AC-1" => { "status" => "Implemented" } } } }

    it "previews without writing" do
      post import_fields_preview_api_v1_ssp_document_path(document.slug),
           params: { file: upload(body) }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["stats"]).to include("changes" => 1)
      expect(control.ssp_control_fields.count).to eq(0)
    end

    it "confirms and applies the change (audited)" do
      post import_fields_confirm_api_v1_ssp_document_path(document.slug),
           params: { file: upload(body) }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["applied"]).to eq(1)
      expect(control.ssp_control_fields.find_by(field_name: "status").field_value).to eq("Implemented")
    end

    it "returns 401 without a token" do
      post import_fields_confirm_api_v1_ssp_document_path(document.slug), params: { file: upload(body) }
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids a member without ssp.write" do
      post import_fields_confirm_api_v1_ssp_document_path(document.slug),
           params: { file: upload(body) }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 422 on a malformed file" do
      post import_fields_confirm_api_v1_ssp_document_path(document.slug),
           params: { file: upload("{ not json") }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/Invalid JSON/)
    end

    it "returns 422 when no file is provided" do
      post import_fields_confirm_api_v1_ssp_document_path(document.slug), headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "CDEF (converters.write authz)" do
    let(:document) { create(:cdef_document) }
    let!(:control) { create(:cdef_control, cdef_document: document, control_id: "AC-1") }
    let(:body) { { "controls" => { "AC-1" => { "notes" => "reviewed" } } } }

    it "confirms and applies for an admin" do
      post import_fields_confirm_api_v1_cdef_document_path(document.slug),
           params: { file: upload(body) }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(control.cdef_control_fields.find_by(field_name: "notes").field_value).to eq("reviewed")
    end

    it "forbids a member without converters.write" do
      post import_fields_confirm_api_v1_cdef_document_path(document.slug),
           params: { file: upload(body) }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
