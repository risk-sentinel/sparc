# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SapDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /sap_documents" do
    it "returns a successful response" do
      get sap_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing documents" do
      create(:sap_document, name: "Test SAP Alpha")
      get sap_documents_path
      expect(response.body).to include("Test SAP Alpha")
    end
  end

  describe "GET /sap_documents/:id" do
    it "shows the document" do
      sap = create(:sap_document, name: "Show SAP")
      get sap_document_path(sap)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show SAP")
    end
  end

  describe "GET /sap_documents/new" do
    it "renders the upload form" do
      get new_sap_document_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /sap_documents/:id" do
    it "deletes a standalone document" do
      sap = create(:sap_document)
      expect {
        delete sap_document_path(sap)
      }.to change(SapDocument, :count).by(-1)
      expect(response).to redirect_to(sap_documents_path)
    end

    it "blocks deletion when referenced by SAR" do
      sap = create(:sap_document)
      create(:sar_document, sap_document: sap)

      expect {
        delete sap_document_path(sap)
      }.not_to change(SapDocument, :count)
      expect(response).to redirect_to(sap_document_path(sap))
    end
  end

  describe "GET /sap_documents/:id/download_json" do
    it "returns JSON export" do
      sap = create(:sap_document)
      get download_json_sap_document_path(sap)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /sap_documents/:id/download_yaml" do
    it "raises OSCAL validation error on empty document" do
      sap = create(:sap_document)
      expect {
        get download_yaml_sap_document_path(sap)
      }.to raise_error(StandardError)
    end
  end

  describe "GET /sap_documents/:id/download_xml" do
    it "raises OSCAL validation error on empty document" do
      sap = create(:sap_document)
      expect {
        get download_xml_sap_document_path(sap)
      }.to raise_error(StandardError)
    end
  end

  describe "PATCH /sap_documents/:id/update_metadata" do
    it "updates document metadata" do
      sap = create(:sap_document, name: "Old SAP")
      patch update_metadata_sap_document_path(sap), params: {
        sap_document: { name: "New SAP" }
      }
      expect(response).to redirect_to(sap_document_path(sap))
      expect(sap.reload.name).to eq("New SAP")
    end
  end

  describe "GET /sap_documents/:id/status" do
    it "returns JSON status" do
      sap = create(:sap_document)
      get status_sap_document_path(sap), as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
