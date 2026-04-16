# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SarDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /sar_documents" do
    it "returns a successful response" do
      get sar_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing documents" do
      create(:sar_document, name: "Test SAR Alpha")
      get sar_documents_path
      expect(response.body).to include("Test SAR Alpha")
    end
  end

  describe "GET /sar_documents/:id" do
    it "shows the document" do
      sar = create(:sar_document, name: "Show SAR")
      get sar_document_path(sar)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show SAR")
    end
  end

  describe "GET /sar_documents/new" do
    it "renders the upload form" do
      get new_sar_document_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /sar_documents/:id" do
    it "deletes a standalone document (leaf node)" do
      sar = create(:sar_document)
      expect {
        delete sar_document_path(sar)
      }.to change(SarDocument, :count).by(-1)
      expect(response).to redirect_to(sar_documents_path)
    end
  end

  describe "GET /sar_documents/:id/download_json" do
    it "returns JSON export" do
      sar = create(:sar_document)
      get download_json_sar_document_path(sar)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /sar_documents/:id/download_yaml" do
    it "returns a response for the document" do
      sar = create(:sar_document)
      get download_yaml_sar_document_path(sar)
      expect(response.status).to be_in([ 200, 302 ])
    end
  end

  describe "GET /sar_documents/:id/download_xml" do
    it "returns a response for the document" do
      sar = create(:sar_document)
      get download_xml_sar_document_path(sar)
      expect(response.status).to be_in([ 200, 302 ])
    end
  end

  describe "PATCH /sar_documents/:id/update_metadata" do
    it "updates document metadata" do
      sar = create(:sar_document, name: "Old SAR")
      patch update_metadata_sar_document_path(sar), params: {
        sar_document: { name: "New SAR" }
      }
      sar.reload
      expect(response).to redirect_to(sar_document_path(sar))
      expect(sar.name).to eq("New SAR")
    end
  end

  describe "GET /sar_documents/:id/status" do
    it "returns JSON status" do
      sar = create(:sar_document)
      get status_sar_document_path(sar), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /sar_documents/wizard" do
    it "renders the wizard form" do
      get wizard_sar_documents_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /sar_documents/create_from_wizard" do
    it "creates a document from wizard" do
      expect {
        post create_from_wizard_sar_documents_path, params: {
          name: "Wizard SAR",
          description: "Test wizard SAR"
        }
      }.to change(SarDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /sar_documents/select_profile" do
    it "returns a successful response" do
      get select_profile_sar_documents_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /sar_documents/create_from_profile" do
    let(:resolved_catalog_json) do
      {
        "catalog" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test Catalog", "oscal-version" => "1.1.2" },
          "groups" => [
            {
              "id" => "ac",
              "class" => "family",
              "title" => "Access Control",
              "controls" => [
                {
                  "id" => "ac-1",
                  "class" => "SP800-53",
                  "title" => "Policy and Procedures",
                  "parts" => [
                    { "id" => "ac-1_smt", "name" => "statement", "prose" => "Develop access control policy." }
                  ]
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
        resolved_catalog_json: resolved_catalog_json,
        published: Time.current.iso8601)
    end

    it "creates a SAR from a published profile and redirects" do
      expect {
        post create_from_profile_sar_documents_path, params: {
          source_profile_id: profile.slug,
          sar_name: "Test SAR from Profile"
        }
      }.to change(SarDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /sar_documents/select_ssp" do
    it "returns a successful response" do
      get select_ssp_sar_documents_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /sar_documents/create_from_ssp" do
    let(:ssp) do
      ssp_doc = create(:ssp_document, status: "completed")
      ctrl = ssp_doc.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures", row_order: 0)
      ctrl.ssp_control_fields.create!(field_name: "stated_requirement", field_value: "Develop access control policy.")
      ctrl.ssp_control_fields.create!(field_name: "status", field_value: "Implemented")
      ssp_doc
    end

    it "creates a SAR from a completed SSP and redirects" do
      expect {
        post create_from_ssp_sar_documents_path, params: {
          source_ssp_id: ssp.slug,
          sar_name: "Test SAR from SSP"
        }
      }.to change(SarDocument, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /sar_documents/:id/associate_source" do
    let(:sar) { create(:sar_document) }
    let(:ssp) do
      ssp = create(:ssp_document)
      ssp_ctrl = ssp.ssp_controls.create!(control_id: "cm-2", title: "Baseline", row_order: 0)
      ssp_ctrl.ssp_control_fields.create!(field_name: "responsible_entities", field_value: "Platform")
      ssp
    end
    let(:sap) { create(:sap_document, ssp_document: ssp) }

    before do
      sar.sar_controls.create!(control_id: "cm-2", title: "Baseline", row_order: 0)
    end

    it "links the SAR to the SAP and back-fills responsibility from the SSP chain" do
      patch associate_source_sar_document_path(sar), params: {
        sar_document: { sap_document_id: sap.id }
      }

      sar.reload
      expect(sar.sap_document_id).to eq(sap.id)
      ctrl = sar.sar_controls.find_by(control_id: "cm-2")
      field = ctrl.sar_control_fields.find_by(field_name: "responsibility")
      expect(field&.field_value).to eq("Platform")
      expect(response).to redirect_to(sar_document_path(sar))
    end

    it "doesn't duplicate fields on re-association" do
      ctrl = sar.sar_controls.first
      ctrl.sar_control_fields.create!(field_name: "responsibility", field_value: "Manually Set")

      patch associate_source_sar_document_path(sar), params: {
        sar_document: { sap_document_id: sap.id }
      }

      counts = ctrl.sar_control_fields.where(field_name: "responsibility").count
      expect(counts).to eq(1)
      expect(ctrl.sar_control_fields.find_by(field_name: "responsibility").field_value)
        .to eq("Manually Set")
    end
  end

  describe "PATCH /sar_documents/:id/update_objective" do
    let(:sar) { create(:sar_document) }
    let(:control) { create(:sar_control, sar_document: sar) }
    let(:objective) { create(:sar_control_objective, sar_control: control, status: "pending") }

    it "updates the objective and stamps assessed_at on terminal status" do
      patch update_objective_sar_document_path(sar), params: {
        objective_id: objective.id,
        sar_control_objective: {
          status: "failed",
          assessor_name: "Bob",
          assessor_notes: "Evidence missing."
        }
      }

      objective.reload
      expect(objective.status).to eq("failed")
      expect(objective.assessor_name).to eq("Bob")
      expect(objective.assessed_at).to be_within(5.seconds).of(Time.current)
    end

    it "does not update an objective belonging to a different SAR" do
      other_sar = create(:sar_document)
      other_objective = create(:sar_control_objective,
                               sar_control: create(:sar_control, sar_document: other_sar),
                               status: "pending")

      patch update_objective_sar_document_path(sar), params: {
        objective_id: other_objective.id,
        sar_control_objective: { status: "passing" }
      }

      expect(other_objective.reload.status).to eq("pending")
    end
  end
end
