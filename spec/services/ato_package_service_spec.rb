# frozen_string_literal: true

require "rails_helper"

RSpec.describe AtoPackageService do
  let(:ab) { create(:authorization_boundary) }

  let(:resolved_catalog_json) do
    {
      "catalog" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => {
          "title" => "Test Resolved Catalog",
          "version" => "1.0.0",
          "oscal-version" => "1.1.2",
          "last-modified" => Time.current.iso8601
        },
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
                "props" => [
                  { "name" => "label", "value" => "AC-1" },
                  { "name" => "priority", "value" => "P1" }
                ],
                "parts" => [
                  { "id" => "ac-1_smt", "name" => "statement", "prose" => "Develop and document access control policy." },
                  { "id" => "ac-1_gdn", "name" => "guidance", "prose" => "Access control policy guidance." }
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

  describe "#create" do
    context "when all steps are skipped" do
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "returns the authorization boundary unchanged" do
        result = described_class.new(ab, params).create

        expect(result).to eq(ab)
        expect(ab.ssp_document).to be_nil
        expect(ab.sap_document).to be_nil
        expect(ab.sar_document).to be_nil
        expect(ab.poam_documents).to be_empty
      end
    end

    context "when selecting an existing SSP" do
      let(:ssp) { create(:ssp_document) }
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "select_existing",
          ssp_document_id: ssp.id,
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "links the SSP to the authorization boundary" do
        described_class.new(ab, params).create

        ssp.reload
        expect(ssp.authorization_boundary).to eq(ab)
        expect(ab.ssp_document).to eq(ssp)
      end
    end

    context "when selecting an existing SAP" do
      let(:sap) { create(:sap_document) }
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "select_existing",
          sap_document_id: sap.id,
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "links the SAP to the authorization boundary" do
        described_class.new(ab, params).create

        sap.reload
        expect(sap.authorization_boundary).to eq(ab)
        expect(ab.sap_document).to eq(sap)
      end
    end

    context "when selecting an existing SAR" do
      let(:sar) { create(:sar_document) }
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "select_existing",
          sar_document_id: sar.id,
          poam_mode: "skip"
        }
      end

      it "links the SAR to the authorization boundary" do
        described_class.new(ab, params).create

        sar.reload
        expect(sar.authorization_boundary).to eq(ab)
        expect(ab.sar_document).to eq(sar)
      end
    end

    context "when selecting an existing POAM" do
      let(:poam) { create(:poam_document) }
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "select_existing",
          poam_document_id: poam.id
        }
      end

      it "links the POAM to the authorization boundary" do
        described_class.new(ab, params).create

        poam.reload
        expect(poam.authorization_boundary).to eq(ab)
        expect(ab.poam_documents).to include(poam)
      end
    end

    context "when selecting existing CDEFs" do
      let(:cdef1) { create(:cdef_document) }
      let(:cdef2) { create(:cdef_document) }
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "select_existing",
          cdef_document_ids: [ cdef1.id.to_s, cdef2.id.to_s ],
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "creates boundary_cdef_documents linking CDEFs to the boundary" do
        described_class.new(ab, params).create

        ab.reload
        expect(ab.cdef_documents).to include(cdef1, cdef2)
      end

      it "creates a default boundary if none exists" do
        expect { described_class.new(ab, params).create }
          .to change { ab.boundaries.count }.by(1)

        boundary = ab.boundaries.first
        expect(boundary.name).to eq("Default")
        expect(boundary.environment).to eq("production")
      end

      it "reuses an existing boundary" do
        create(:boundary, authorization_boundary: ab, name: "Existing", environment: "production")

        expect { described_class.new(ab, params).create }
          .not_to change { ab.boundaries.count }
      end
    end

    context "when creating a new SSP" do
      let(:params) do
        {
          profile_mode: "select_existing",
          profile_document_id: profile.id,
          cdef_mode: "skip",
          ssp_mode: "create_new",
          ssp_name: "New SSP",
          ssp_description: "A test SSP",
          system_status: "operational",
          security_sensitivity_level: "fips-199-moderate",
          security_objective_confidentiality: "fips-199-moderate",
          security_objective_integrity: "fips-199-moderate",
          security_objective_availability: "fips-199-low",
          authorization_boundary_description: "Test boundary description",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "delegates to SspWizardService and links the SSP" do
        fake_ssp = create(:ssp_document, :wizard, name: "New SSP")
        wizard = instance_double(SspWizardService, create: fake_ssp)
        allow(SspWizardService).to receive(:new).and_return(wizard)

        described_class.new(ab, params).create

        expect(SspWizardService).to have_received(:new) do |arg|
          expect(arg[:name]).to eq("New SSP")
          expect(arg[:profile_document_id]).to eq(profile.id)
          expect(arg[:system_status]).to eq("operational")
        end
        fake_ssp.reload
        expect(fake_ssp.authorization_boundary).to eq(ab)
      end

      it "uses a default name when ssp_name is blank" do
        blank_name_params = params.merge(ssp_name: "")
        fake_ssp = create(:ssp_document, :wizard)
        wizard = instance_double(SspWizardService, create: fake_ssp)
        allow(SspWizardService).to receive(:new).and_return(wizard)

        described_class.new(ab, blank_name_params).create

        expect(SspWizardService).to have_received(:new) do |arg|
          expect(arg[:name]).to eq("SSP for #{ab.name}")
        end
      end
    end

    context "when creating a new SAP" do
      let(:ssp) { create(:ssp_document) }
      let(:params) do
        {
          profile_mode: "skip",
          profile_document_id: profile.id,
          cdef_mode: "skip",
          ssp_mode: "select_existing",
          ssp_document_id: ssp.id,
          sap_mode: "create_new",
          sap_name: "New SAP",
          sap_description: "Assessment plan",
          assessment_type: "annual",
          assessment_start: "2026-04-01",
          assessment_end: "2026-04-30",
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "delegates to SapGeneratorService and links the SAP" do
        fake_sap = create(:sap_document, name: "New SAP")
        generator = instance_double(SapGeneratorService, generate: fake_sap)
        allow(SapGeneratorService).to receive(:new).and_return(generator)

        described_class.new(ab, params).create

        expect(SapGeneratorService).to have_received(:new) do |**kwargs|
          expect(kwargs[:name]).to eq("New SAP")
          expect(kwargs[:assessment_type]).to eq("annual")
        end
        fake_sap.reload
        expect(fake_sap.authorization_boundary).to eq(ab)
      end
    end

    context "when creating a new SAR" do
      let(:sap) { create(:sap_document) }
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "select_existing",
          sap_document_id: sap.id,
          sar_mode: "create_new",
          sar_name: "New SAR",
          sar_description: "Assessment results",
          sar_assessment_start: "2026-04-01",
          sar_assessment_end: "2026-04-30",
          poam_mode: "skip"
        }
      end

      it "delegates to SarWizardService and links the SAR" do
        fake_sar = create(:sar_document, :wizard, name: "New SAR")
        wizard = instance_double(SarWizardService, create: fake_sar)
        allow(SarWizardService).to receive(:new).and_return(wizard)

        described_class.new(ab, params).create

        expect(SarWizardService).to have_received(:new) do |arg|
          expect(arg[:name]).to eq("New SAR")
          expect(arg[:sap_document_id]).to eq(sap.id)
        end
        fake_sar.reload
        expect(fake_sar.authorization_boundary).to eq(ab)
      end
    end

    context "when creating a new POAM" do
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "create_new",
          poam_name: "New POAM",
          poam_description: "Tracking findings"
        }
      end

      it "creates a PoamDocument directly and links to the boundary" do
        expect {
          described_class.new(ab, params).create
        }.to change(PoamDocument, :count).by(1)

        poam = PoamDocument.last
        expect(poam.name).to eq("New POAM")
        expect(poam.description).to eq("Tracking findings")
        expect(poam.status).to eq("completed")
        expect(poam.lifecycle_status).to eq("started")
        expect(poam.authorization_boundary).to eq(ab)
      end

      it "uses a default name when poam_name is blank" do
        blank_name_params = params.merge(poam_name: "")

        described_class.new(ab, blank_name_params).create

        poam = PoamDocument.last
        expect(poam.name).to eq("POA&M for #{ab.name}")
      end
    end

    context "mixed mode: some create, some select, some skip" do
      let(:existing_sap) { create(:sap_document) }
      let(:cdef) { create(:cdef_document) }
      let(:params) do
        {
          profile_mode: "skip",
          profile_document_id: profile.id,
          cdef_mode: "select_existing",
          cdef_document_ids: [ cdef.id.to_s ],
          ssp_mode: "create_new",
          ssp_name: "Mixed SSP",
          sap_mode: "select_existing",
          sap_document_id: existing_sap.id,
          sar_mode: "skip",
          poam_mode: "create_new",
          poam_name: "Mixed POAM"
        }
      end

      it "handles a mix of create_new, select_existing, and skip" do
        fake_ssp = create(:ssp_document, :wizard, name: "Mixed SSP")
        wizard = instance_double(SspWizardService, create: fake_ssp)
        allow(SspWizardService).to receive(:new).and_return(wizard)

        result = described_class.new(ab, params).create

        expect(result).to eq(ab)

        # SSP was created via wizard and linked
        fake_ssp.reload
        expect(fake_ssp.authorization_boundary).to eq(ab)

        # SAP was selected and linked
        existing_sap.reload
        expect(existing_sap.authorization_boundary).to eq(ab)

        # CDEF was linked through boundary
        ab.reload
        expect(ab.cdef_documents).to include(cdef)

        # POAM was created directly
        poam = PoamDocument.find_by(name: "Mixed POAM")
        expect(poam).to be_present
        expect(poam.authorization_boundary).to eq(ab)

        # SAR was skipped
        expect(ab.sar_document).to be_nil
      end
    end

    context "transaction behavior" do
      it "wraps all steps in a transaction" do
        params = {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "select_existing",
          poam_document_id: -1 # will raise ActiveRecord::RecordNotFound
        }

        expect {
          described_class.new(ab, params).create
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
