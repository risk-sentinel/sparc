# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SspDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /ssp_documents" do
    it "returns a successful response" do
      get ssp_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing documents" do
      ssp = create(:ssp_document, name: "Test SSP Alpha")
      get ssp_documents_path
      expect(response.body).to include("Test SSP Alpha")
    end
  end

  describe "GET /ssp_documents/:id" do
    it "shows the document" do
      ssp = create(:ssp_document, name: "Show SSP")
      get ssp_document_path(ssp)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show SSP")
    end
  end

  describe "GET /ssp_documents/new" do
    it "renders the upload form" do
      get new_ssp_document_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /ssp_documents" do
    it "renders the form when no file provided" do
      post ssp_documents_path, params: { ssp_document: { name: "No File" } }
      # Controller renders the new template or redirects depending on path
      expect(response.status).to be_in([ 200, 302 ])
    end
  end

  describe "DELETE /ssp_documents/:id" do
    it "deletes a standalone document" do
      ssp = create(:ssp_document)
      expect {
        delete ssp_document_path(ssp)
      }.to change(SspDocument, :count).by(-1)
      expect(response).to redirect_to(ssp_documents_path)
    end

    it "blocks deletion when referenced by SAP" do
      ssp = create(:ssp_document)
      create(:sap_document, ssp_document: ssp)

      expect {
        delete ssp_document_path(ssp)
      }.not_to change(SspDocument, :count)
      expect(response).to redirect_to(ssp_document_path(ssp))
    end
  end

  describe "GET /ssp_documents/:id/download_json" do
    it "returns JSON export" do
      ssp = create(:ssp_document)
      get download_json_ssp_document_path(ssp)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /ssp_documents/:id/download_yaml" do
    it "raises validation error on empty document" do
      ssp = create(:ssp_document)
      expect {
        get download_yaml_ssp_document_path(ssp)
      }.to raise_error(StandardError)
    end
  end

  describe "GET /ssp_documents/:id/download_xml" do
    it "raises validation error on empty document" do
      ssp = create(:ssp_document)
      expect {
        get download_xml_ssp_document_path(ssp)
      }.to raise_error(StandardError)
    end
  end

  describe "PATCH /ssp_documents/:id/update_metadata" do
    it "updates document metadata" do
      ssp = create(:ssp_document, name: "Old Name")
      patch update_metadata_ssp_document_path(ssp), params: {
        ssp_document: { name: "New Name" }
      }
      expect(response).to redirect_to(ssp_document_path(ssp))
      expect(ssp.reload.name).to eq("New Name")
    end
  end

  describe "GET /ssp_documents/:id/status" do
    it "returns JSON status" do
      ssp = create(:ssp_document)
      get status_ssp_document_path(ssp), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /ssp_documents/:id/wizard" do
    it "renders the wizard form" do
      get wizard_ssp_documents_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /ssp_documents/select_profile" do
    it "returns a successful response" do
      get select_profile_ssp_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "shows only published profiles with resolved catalogs" do
      published = create(:profile_document,
        lifecycle_status: "published",
        resolved_catalog_json: { "catalog" => { "groups" => [] } },
        published: Time.current.iso8601)
      unpublished = create(:profile_document, lifecycle_status: "in_progress")

      get select_profile_ssp_documents_path
      expect(response.body).to include(published.name)
      expect(response.body).not_to include(unpublished.name)
    end
  end

  describe "POST /ssp_documents/create_from_profile" do
    let(:resolved_catalog_json) do
      {
        "catalog" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test Catalog", "oscal-version" => "1.1.2" },
          "groups" => [
            {
              "id" => "ac",
              "controls" => [
                { "id" => "ac-1", "title" => "Policy and Procedures", "parts" => [] }
              ]
            }
          ]
        }
      }
    end

    let(:profile) do
      create(:profile_document,
        lifecycle_status: "published",
        resolved_catalog_json: resolved_catalog_json,
        published: Time.current.iso8601)
    end

    it "creates an SSP and redirects" do
      expect {
        post create_from_profile_ssp_documents_path, params: {
          source_profile_id: profile.slug,
          ssp_name: "Test SSP from Profile"
        }
      }.to change(SspDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "redirects with error for nonexistent profile" do
      post create_from_profile_ssp_documents_path, params: {
        source_profile_id: "nonexistent-slug",
        ssp_name: "Bad SSP"
      }
      expect(response).to redirect_to(select_profile_ssp_documents_path)
      expect(flash[:error]).to include("not found")
    end
  end

  describe "POST /ssp_documents/create_from_wizard" do
    it "creates a document from wizard with profile" do
      profile = create(:profile_document)
      expect {
        post create_from_wizard_ssp_documents_path, params: {
          name: "Wizard SSP",
          profile_document_id: profile.id
        }
      }.to change(SspDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "redirects with error when wizard fails" do
      post create_from_wizard_ssp_documents_path, params: { name: "No Profile" }
      expect(response).to redirect_to(wizard_ssp_documents_path)
    end
  end
end
