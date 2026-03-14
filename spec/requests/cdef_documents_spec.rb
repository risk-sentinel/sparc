# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CdefDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /cdef_documents" do
    it "returns a successful response" do
      get cdef_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "is accessible without authentication" do
      # CdefDocumentsController skips require_authentication for index/show
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(nil)
      allow_any_instance_of(ApplicationController).to receive(:signed_in?).and_return(false)
      get cdef_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing documents" do
      create(:cdef_document, name: "Test CDEF Alpha")
      get cdef_documents_path
      expect(response.body).to include("Test CDEF Alpha")
    end
  end

  describe "GET /cdef_documents/:id" do
    it "shows the document" do
      cdef = create(:cdef_document, name: "Show CDEF")
      get cdef_document_path(cdef)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show CDEF")
    end
  end

  describe "GET /cdef_documents/new" do
    it "renders the upload form" do
      get new_cdef_document_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /cdef_documents/:id" do
    it "deletes a standalone document" do
      cdef = create(:cdef_document)
      expect {
        delete cdef_document_path(cdef)
      }.to change(CdefDocument, :count).by(-1)
      expect(response).to redirect_to(cdef_documents_path)
    end

    it "blocks deletion when linked to SSP via join table" do
      cdef = create(:cdef_document)
      ssp = create(:ssp_document)
      create(:ssp_document_cdef_document, ssp_document: ssp, cdef_document: cdef)

      expect {
        delete cdef_document_path(cdef)
      }.not_to change(CdefDocument, :count)
      expect(response).to redirect_to(cdef_document_path(cdef))
    end
  end

  describe "POST /cdef_documents/:id/copy" do
    it "duplicates the document" do
      cdef = create(:cdef_document, name: "Original CDEF")
      expect {
        post copy_cdef_document_path(cdef)
      }.to change(CdefDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /cdef_documents/:id/download_json" do
    it "returns JSON export" do
      cdef = create(:cdef_document)
      get download_json_cdef_document_path(cdef)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /cdef_documents/:id/download_yaml" do
    it "raises OSCAL validation error on empty document" do
      cdef = create(:cdef_document)
      expect {
        get download_yaml_cdef_document_path(cdef)
      }.to raise_error(StandardError)
    end
  end

  describe "GET /cdef_documents/:id/download_xml" do
    it "raises OSCAL validation error on empty document" do
      cdef = create(:cdef_document)
      expect {
        get download_xml_cdef_document_path(cdef)
      }.to raise_error(StandardError)
    end
  end

  describe "PATCH /cdef_documents/:id/update_metadata" do
    it "updates document metadata" do
      cdef = create(:cdef_document, name: "Old CDEF")
      patch update_metadata_cdef_document_path(cdef), params: {
        cdef_document: { name: "New CDEF" }
      }
      expect(response).to redirect_to(cdef_document_path(cdef))
      expect(cdef.reload.name).to eq("New CDEF")
    end
  end

  describe "GET /cdef_documents/:id/status" do
    it "returns JSON status" do
      cdef = create(:cdef_document)
      get status_cdef_document_path(cdef), as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
