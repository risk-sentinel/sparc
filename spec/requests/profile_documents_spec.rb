# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ProfileDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /profile_documents" do
    it "returns a successful response" do
      get profile_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "is accessible without authentication" do
      # ProfileDocumentsController skips require_authentication for index/show
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(nil)
      allow_any_instance_of(ApplicationController).to receive(:signed_in?).and_return(false)
      get profile_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing documents" do
      create(:profile_document, name: "Test Profile Alpha")
      get profile_documents_path
      expect(response.body).to include("Test Profile Alpha")
    end
  end

  describe "GET /profile_documents/:id" do
    it "shows the document" do
      profile = create(:profile_document, name: "Show Profile")
      get profile_document_path(profile)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show Profile")
    end
  end

  describe "GET /profile_documents/new" do
    it "renders the upload form" do
      get new_profile_document_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /profile_documents/:id" do
    it "deletes a standalone document" do
      profile = create(:profile_document)
      expect {
        delete profile_document_path(profile)
      }.to change(ProfileDocument, :count).by(-1)
      expect(response).to redirect_to(profile_documents_path)
    end

    it "blocks deletion when referenced by SSP" do
      profile = create(:profile_document)
      create(:ssp_document, profile_document: profile)

      expect {
        delete profile_document_path(profile)
      }.not_to change(ProfileDocument, :count)
      expect(response).to redirect_to(profile_document_path(profile))
    end

    it "blocks deletion when referenced by SAP" do
      profile = create(:profile_document)
      create(:sap_document, profile_document: profile)

      expect {
        delete profile_document_path(profile)
      }.not_to change(ProfileDocument, :count)
      expect(response).to redirect_to(profile_document_path(profile))
    end
  end

  describe "POST /profile_documents/:id/copy" do
    it "duplicates the document" do
      profile = create(:profile_document, name: "Original Profile")
      expect {
        post copy_profile_document_path(profile)
      }.to change(ProfileDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /profile_documents/:id/download_json" do
    it "returns JSON export" do
      profile = create(:profile_document)
      get download_json_profile_document_path(profile)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /profile_documents/:id/download_yaml" do
    it "raises OSCAL validation error on empty document" do
      profile = create(:profile_document)
      expect {
        get download_yaml_profile_document_path(profile)
      }.to raise_error(StandardError)
    end
  end

  describe "GET /profile_documents/:id/download_xml" do
    it "raises OSCAL validation error on empty document" do
      profile = create(:profile_document)
      expect {
        get download_xml_profile_document_path(profile)
      }.to raise_error(StandardError)
    end
  end

  describe "PATCH /profile_documents/:id/update_metadata" do
    it "updates document metadata" do
      profile = create(:profile_document, name: "Old Profile")
      patch update_metadata_profile_document_path(profile), params: {
        profile_document: { name: "New Profile" }
      }
      profile.reload
      expect(response).to redirect_to(profile_document_path(profile))
      expect(profile.name).to eq("New Profile")
    end
  end

  describe "GET /profile_documents/:id/status" do
    it "returns JSON status" do
      profile = create(:profile_document)
      get status_profile_document_path(profile), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /profile_documents/select_catalog" do
    it "renders the catalog selection page" do
      get select_catalog_profile_documents_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /profile_documents/create_from_catalog" do
    it "creates a profile from catalog controls" do
      catalog = create(:control_catalog)
      family = create(:control_family, control_catalog: catalog)
      control = create(:catalog_control, control_family: family)

      expect {
        post create_from_catalog_profile_documents_path, params: {
          catalog_id: catalog.slug,
          control_ids: [ control.control_id ],
          profile_name: "From Catalog Profile"
        }
      }.to change(ProfileDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end
end
