# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /poam_documents" do
    it "returns a successful response" do
      get poam_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing documents" do
      create(:poam_document, name: "Test POAM Alpha")
      get poam_documents_path
      expect(response.body).to include("Test POAM Alpha")
    end
  end

  describe "GET /poam_documents/:id" do
    it "shows the document" do
      poam = create(:poam_document, name: "Show POAM")
      get poam_document_path(poam)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show POAM")
    end
  end

  describe "GET /poam_documents/new" do
    it "renders the upload form" do
      get new_poam_document_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /poam_documents/:id" do
    it "deletes a standalone document (leaf node)" do
      poam = create(:poam_document)
      expect {
        delete poam_document_path(poam)
      }.to change(PoamDocument, :count).by(-1)
      expect(response).to redirect_to(poam_documents_path)
    end
  end

  describe "GET /poam_documents/:id/download_json" do
    it "returns JSON export" do
      poam = create(:poam_document)
      get download_json_poam_document_path(poam)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /poam_documents/:id/download_yaml" do
    it "raises OSCAL validation error on empty document" do
      poam = create(:poam_document)
      expect {
        get download_yaml_poam_document_path(poam)
      }.to raise_error(StandardError)
    end
  end

  describe "GET /poam_documents/:id/download_xml" do
    it "raises OSCAL validation error on empty document" do
      poam = create(:poam_document)
      expect {
        get download_xml_poam_document_path(poam)
      }.to raise_error(StandardError)
    end
  end

  describe "PATCH /poam_documents/:id/update_metadata" do
    it "updates document metadata" do
      poam = create(:poam_document, name: "Old POAM")
      patch update_metadata_poam_document_path(poam), params: {
        poam_document: { name: "New POAM" }
      }
      expect(response).to redirect_to(poam_document_path(poam))
      expect(poam.reload.name).to eq("New POAM")
    end
  end

  describe "GET /poam_documents/:id/status" do
    it "returns JSON status" do
      poam = create(:poam_document)
      get status_poam_document_path(poam), as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
