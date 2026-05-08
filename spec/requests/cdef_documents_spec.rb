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

    it "renders the shared OSCAL export dropdown for completed docs (#451 A1)" do
      create(:cdef_document, status: "completed")
      get cdef_documents_path
      # Stimulus controller marker confirms the shared partial replaced the
      # plain-link inline dropdown — clicks now route through the validation
      # modal that surfaces specific errors.
      expect(response.body).to include('data-controller="oscal-export"')
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

  describe "GET /cdef_documents/:id/download_yaml (#451)" do
    it "redirects with flash warning when validation fails (no 500)" do
      cdef = create(:cdef_document)
      get download_yaml_cdef_document_path(cdef)
      expect(response).to redirect_to(
        cdef_document_path(cdef, oscal_validation_failed: 1, oscal_format: "yaml")
      )
      expect(flash[:warning]).to match(/schema validation/i)
    end

    it "honors skip_validation=1 to emit unvalidated YAML" do
      cdef = create(:cdef_document)
      get download_yaml_cdef_document_path(cdef, skip_validation: 1)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/x-yaml")
    end
  end

  describe "GET /cdef_documents/:id/download_xml (#451)" do
    it "redirects with flash warning when validation fails (no 500)" do
      cdef = create(:cdef_document)
      get download_xml_cdef_document_path(cdef)
      expect(response).to redirect_to(
        cdef_document_path(cdef, oscal_validation_failed: 1, oscal_format: "xml")
      )
      expect(flash[:warning]).to match(/schema validation/i)
    end

    it "honors skip_validation=1 to emit unvalidated XML" do
      cdef = create(:cdef_document)
      get download_xml_cdef_document_path(cdef, skip_validation: 1)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
    end
  end

  describe "PATCH /cdef_documents/:id/update_metadata" do
    it "updates document metadata" do
      cdef = create(:cdef_document, name: "Old CDEF")
      patch update_metadata_cdef_document_path(cdef), params: {
        cdef_document: { name: "New CDEF" }
      }
      cdef.reload
      expect(response).to redirect_to(cdef_document_path(cdef))
      expect(cdef.name).to eq("New CDEF")
    end
  end

  describe "GET /cdef_documents/:id/status" do
    it "returns JSON status" do
      cdef = create(:cdef_document)
      get status_cdef_document_path(cdef), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /cdef_documents/select_profile" do
    it "renders the profile selection page" do
      get select_profile_cdef_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "lists published profiles with resolved catalogs" do
      published = create(:profile_document,
        name: "Published Baseline",
        lifecycle_status: "published",
        resolved_catalog_json: { "catalog" => { "groups" => [] } })
      unpublished = create(:profile_document, name: "Draft Profile", lifecycle_status: "in_progress")

      get select_profile_cdef_documents_path

      expect(response.body).to include("Published Baseline")
      expect(response.body).not_to include("Draft Profile")
    end
  end

  describe "POST /cdef_documents/create_from_profile" do
    let(:resolved_catalog) do
      {
        "catalog" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test", "oscal-version" => "1.1.2" },
          "groups" => [
            {
              "id" => "ac", "title" => "Access Control",
              "controls" => [
                {
                  "id" => "ac-1", "title" => "Policy",
                  "props" => [ { "name" => "priority", "value" => "P1" } ],
                  "parts" => [ { "name" => "statement", "prose" => "Test statement" } ]
                }
              ]
            }
          ]
        }
      }
    end

    let(:profile) do
      create(:profile_document,
        lifecycle_status: "published",
        resolved_catalog_json: resolved_catalog,
        published: Time.current.iso8601)
    end

    it "creates a CDEF from a published profile" do
      expect {
        post create_from_profile_cdef_documents_path, params: {
          source_profile_id: profile.slug,
          cdef_name: "My New CDEF"
        }
      }.to change(CdefDocument, :count).by(1)

      cdef = CdefDocument.last
      expect(cdef.name).to eq("My New CDEF")
      expect(cdef.cdef_controls.count).to eq(1)
      expect(response).to redirect_to(cdef_document_path(cdef))
    end

    it "redirects with error for unpublished profile" do
      unpublished = create(:profile_document, lifecycle_status: "in_progress")

      post create_from_profile_cdef_documents_path, params: {
        source_profile_id: unpublished.slug
      }

      expect(response).to redirect_to(select_profile_cdef_documents_path)
      expect(flash[:error]).to include("published")
    end

    it "redirects with error for nonexistent profile" do
      post create_from_profile_cdef_documents_path, params: {
        source_profile_id: "nonexistent-slug"
      }

      expect(response).to redirect_to(select_profile_cdef_documents_path)
      expect(flash[:error]).to include("not found")
    end
  end
end
