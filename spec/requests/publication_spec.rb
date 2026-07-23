# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Publication workflow", type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  # #785 — these specs cover publication mechanics, not the approval gate.
  # The gate now defaults ON, so pin it off rather than depend on the default.
  before { allow(SparcConfig).to receive(:require_document_approval?).and_return(false) }

  # Valid metadata that passes PublicationValidationService
  let(:valid_metadata) do
    party_uuid = SecureRandom.uuid
    {
      "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
      "parties" => [ { "uuid" => party_uuid, "type" => "organization", "name" => "Test Org" } ],
      "responsible-parties" => [ { "role-id" => "prepared-by", "party-uuids" => [ party_uuid ] } ]
    }
  end

  # Shared examples for all document types that use the Publishable concern.
  # `content_setup` (#627) adds the type's required content so the document is
  # content-complete and the publish gate lets it through; types without a
  # ContentCompleteness requirement pass nil (no-op).
  shared_examples "publishable document" do |factory:, path_helper:, check_path_helper:, content_setup: nil|
    let(:document) do
      doc = create(factory, lifecycle_status: "in_progress", metadata_extra: valid_metadata)
      instance_exec(doc, &content_setup) if content_setup
      doc
    end
    let(:document_without_metadata) { create(factory, lifecycle_status: "in_progress") }
    let(:published_document) do
      doc = create(factory, lifecycle_status: "published", metadata_extra: valid_metadata)
      instance_exec(doc, &content_setup) if content_setup
      doc
    end

    describe "GET publish_check" do
      it "returns JSON readiness data" do
        get send(check_path_helper, document)
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to include("ready", "errors", "missing_fields", "checks")
      end

      it "returns ready: true for document with complete metadata" do
        get send(check_path_helper, document)
        json = JSON.parse(response.body)
        expect(json["ready"]).to be true
      end

      it "returns ready: false for document without metadata" do
        get send(check_path_helper, document_without_metadata)
        json = JSON.parse(response.body)
        expect(json["ready"]).to be false
        expect(json["errors"]).not_to be_empty
      end
    end

    describe "PATCH publish" do
      it "publishes a document with valid metadata" do
        patch send(path_helper, document)
        expect(response).to have_http_status(:redirect)
        expect(document.reload.lifecycle_status).to eq("published")
      end

      it "rejects publishing without required metadata" do
        patch send(path_helper, document_without_metadata)
        expect(response).to have_http_status(:redirect)
        expect(document_without_metadata.reload.lifecycle_status).not_to eq("published")
        expect(flash[:error]).to include("Cannot publish")
      end

      it "blocks publishing an already-published document" do
        patch send(path_helper, published_document)
        expect(response).to have_http_status(:redirect)
        expect(flash[:error]).to include("published")
      end

      it "creates an audit event" do
        expect {
          patch send(path_helper, document)
        }.to change(AuditEvent, :count).by(1)
      end
    end
  end

  context "SSP Documents" do
    it_behaves_like "publishable document",
      factory: :ssp_document,
      path_helper: :publish_ssp_document_path,
      check_path_helper: :publish_check_ssp_document_path,
      content_setup: ->(doc) {
        doc.update!(system_id: "SYS-1")
        create(:ssp_control, ssp_document: doc)
      }
  end

  context "SAR Documents" do
    it_behaves_like "publishable document",
      factory: :sar_document,
      path_helper: :publish_sar_document_path,
      check_path_helper: :publish_check_sar_document_path
  end

  context "SAP Documents" do
    it_behaves_like "publishable document",
      factory: :sap_document,
      path_helper: :publish_sap_document_path,
      check_path_helper: :publish_check_sap_document_path
  end

  context "CDEF Documents" do
    it_behaves_like "publishable document",
      factory: :cdef_document,
      path_helper: :publish_cdef_document_path,
      check_path_helper: :publish_check_cdef_document_path,
      content_setup: ->(doc) { create(:cdef_control, cdef_document: doc) }
  end

  context "POA&M Documents" do
    it_behaves_like "publishable document",
      factory: :poam_document,
      path_helper: :publish_poam_document_path,
      check_path_helper: :publish_check_poam_document_path
  end

  context "Control Catalogs" do
    it_behaves_like "publishable document",
      factory: :control_catalog,
      path_helper: :publish_control_catalog_path,
      check_path_helper: :publish_check_control_catalog_path
  end
end
