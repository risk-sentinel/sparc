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

  describe "GET /poam_documents/:id/download_yaml (#451)" do
    it "redirects with flash warning when validation fails (no 500)" do
      poam = create(:poam_document)
      get download_yaml_poam_document_path(poam)
      expect(response).to redirect_to(
        poam_document_path(poam, oscal_validation_failed: 1, oscal_format: "yaml")
      )
      expect(flash[:warning]).to match(/schema validation/i)
    end

    it "honors skip_validation=1 to emit unvalidated YAML" do
      poam = create(:poam_document)
      get download_yaml_poam_document_path(poam, skip_validation: 1)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/x-yaml")
    end
  end

  describe "GET /poam_documents/:id/download_xml (#451)" do
    it "redirects with flash warning when validation fails (no 500)" do
      poam = create(:poam_document)
      get download_xml_poam_document_path(poam)
      expect(response).to redirect_to(
        poam_document_path(poam, oscal_validation_failed: 1, oscal_format: "xml")
      )
      expect(flash[:warning]).to match(/schema validation/i)
    end

    it "honors skip_validation=1 to emit unvalidated XML" do
      poam = create(:poam_document)
      get download_xml_poam_document_path(poam, skip_validation: 1)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
    end
  end

  describe "PATCH /poam_documents/:id/update_metadata" do
    it "updates document metadata" do
      poam = create(:poam_document, name: "Old POAM")
      patch update_metadata_poam_document_path(poam), params: {
        poam_document: { name: "New POAM" }
      }
      poam.reload
      expect(response).to redirect_to(poam_document_path(poam))
      expect(poam.name).to eq("New POAM")
    end
  end

  describe "GET /poam_documents/:id/status" do
    it "returns JSON status" do
      poam = create(:poam_document)
      get status_poam_document_path(poam), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  # ── Wizard create (#389) ──────────────────────────────────────────────

  describe "POST /poam_documents (wizard, #389)" do
    # Deterministic boundary names — Faker can roll names with apostrophes
    # (e.g. "O'Kon ATO") that get HTML-escaped on render and break raw-string
    # assertions on response.body.
    let(:boundary) { create(:authorization_boundary, name: "Wizard Boundary One") }
    let!(:ssp)     { create(:ssp_document, name: "Linked SSP", authorization_boundary: boundary) }

    it "creates a POAM with explicit version + ssp_document_id" do
      post poam_documents_path, params: {
        poam_document: {
          name: "Wizard POAM Explicit",
          description: "Created via wizard",
          system_id: "SYS-001",
          authorization_boundary_id: boundary.id,
          poam_version: "2.5.0",
          oscal_version: "1.1.2",
          ssp_document_id: ssp.id
        }
      }
      poam = PoamDocument.find_by(name: "Wizard POAM Explicit")
      expect(poam).to be_present
      expect(poam.poam_version).to eq("2.5.0")
      expect(poam.oscal_version).to eq("1.1.2")
      expect(poam.ssp_document_id).to eq(ssp.id)
      expect(response).to redirect_to(poam_document_path(poam))
    end

    it "applies defaults when version fields are blank" do
      post poam_documents_path, params: {
        poam_document: {
          name: "Wizard POAM Defaults",
          description: "Defaulted versions",
          poam_version: "",
          oscal_version: ""
        }
      }
      poam = PoamDocument.find_by(name: "Wizard POAM Defaults")
      expect(poam.poam_version).to eq("1.0.0")
      expect(poam.oscal_version).to eq("1.1.2")
    end

    it "renders wizard with SSP options grouped by boundary" do
      ssp_other_boundary = create(:authorization_boundary, name: "Wizard Boundary Two")
      create(:ssp_document, name: "Other Boundary SSP",
             authorization_boundary: ssp_other_boundary)

      get new_poam_document_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Source SSP")
      expect(response.body).to include("Linked SSP")
      expect(response.body).to include("Other Boundary SSP")
      # optgroup labels carry the boundary names (HTML-escaped on render)
      expect(response.body).to include(CGI.escapeHTML(boundary.name))
      expect(response.body).to include(CGI.escapeHTML(ssp_other_boundary.name))
    end
  end

  # ── Empty-items publish-readiness warning (#389) ──────────────────────

  describe "GET /poam_documents/:id show (#389 warning banner)" do
    it "shows the warning banner when no items and not yet published" do
      poam = create(:poam_document, name: "No Items Yet", lifecycle_status: "in_progress")
      get poam_document_path(poam)
      expect(response.body).to include("Add at least one POA&amp;M item before publishing")
    end

    it "hides the warning when items are present" do
      poam = create(:poam_document, name: "Has Items", lifecycle_status: "in_progress")
      create(:poam_item, poam_document: poam)
      get poam_document_path(poam)
      expect(response.body).not_to include("Add at least one POA&amp;M item before publishing")
    end

    it "hides the warning once the document is published" do
      poam = create(:poam_document, name: "Published Empty", lifecycle_status: "published")
      get poam_document_path(poam)
      expect(response.body).not_to include("Add at least one POA&amp;M item before publishing")
    end
  end
end
