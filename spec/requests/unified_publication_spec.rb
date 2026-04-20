# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Unified publication lifecycle", type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  let(:party_uuid) { SecureRandom.uuid }
  let(:valid_metadata) do
    {
      "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
      "parties" => [ { "uuid" => party_uuid, "type" => "organization", "name" => "Test Org" } ],
      "responsible-parties" => [ { "role-id" => "prepared-by", "party-uuids" => [ party_uuid ] } ]
    }
  end

  # ── Profile Publication ──────────────────────────────────────────────

  describe "Profile publication" do
    let(:catalog) { create(:control_catalog) }
    let(:profile) do
      create(:profile_document,
             lifecycle_status: "in_progress",
             metadata_extra: valid_metadata,
             control_catalog: catalog)
    end

    it "publishes a profile with valid metadata and catalog" do
      patch publish_profile_document_path(profile)
      profile.reload
      expect(profile.lifecycle_status).to eq("published")
      expect(profile.resolved_catalog_json).to be_present
      expect(flash[:success]).to include("Profile published successfully")
    end

    it "rejects publishing without a catalog link" do
      profile.update!(control_catalog: nil)
      patch publish_profile_document_path(profile)
      profile.reload
      expect(profile.lifecycle_status).not_to eq("published")
      expect(flash[:error]).to include("no source catalog")
    end

    it "rejects publishing when controls lack prioritization" do
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: nil)
      patch publish_profile_document_path(profile)
      profile.reload
      expect(profile.lifecycle_status).not_to eq("published")
      expect(flash[:error]).to include("missing prioritization")
    end

    it "publishes when all controls have priorities" do
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
      patch publish_profile_document_path(profile)
      profile.reload
      expect(profile.lifecycle_status).to eq("published")
    end

    it "rejects publishing with missing metadata" do
      profile.update!(metadata_extra: {})
      patch publish_profile_document_path(profile)
      profile.reload
      expect(profile.lifecycle_status).not_to eq("published")
      expect(flash[:error]).to include("Cannot publish")
    end

    it "applies inline metadata fixes from the publish modal" do
      profile.update!(metadata_extra: {})
      patch publish_profile_document_path(profile), params: {
        metadata_fixes: {
          roles: [ { "id" => "prepared-by", "title" => "Prepared By" } ].to_json,
          parties: [ { "uuid" => party_uuid, "type" => "organization", "name" => "Fix Org" } ].to_json,
          responsible_parties: [ { "role-id" => "prepared-by", "party-uuids" => [ party_uuid ] } ].to_json
        }
      }
      profile.reload
      expect(profile.lifecycle_status).to eq("published")
      expect(profile.metadata_extra["roles"].first["id"]).to eq("prepared-by")
    end

    it "returns publish_check JSON readiness data with prioritization check" do
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
      get publish_check_profile_document_path(profile)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to include("ready", "checks")
      expect(json["checks"]["controls_prioritized"]).to be true
      expect(json["ready"]).to be true
    end

    it "returns ready: false when controls lack prioritization" do
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: nil)
      get publish_check_profile_document_path(profile)
      json = JSON.parse(response.body)
      expect(json["ready"]).to be false
      expect(json["checks"]["controls_prioritized"]).to be false
      expect(json["errors"]).to include(match(/missing prioritization/))
    end

    it "blocks publishing an already-published profile" do
      profile.update!(lifecycle_status: "published")
      patch publish_profile_document_path(profile)
      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to include("published")
    end

    it "creates an audit event on publish" do
      expect {
        patch publish_profile_document_path(profile)
      }.to change(AuditEvent, :count).by(1)
    end
  end

  # ── Version Auto-Increment ──────────────────────────────────────────

  describe "Version auto-increment" do
    let(:catalog) { create(:control_catalog) }

    it "sets version to 1.0.0 when nil on publish" do
      profile = create(:profile_document,
                       lifecycle_status: "in_progress",
                       metadata_extra: valid_metadata,
                       control_catalog: catalog,
                       profile_version: nil)
      patch publish_profile_document_path(profile)
      expect(profile.reload.profile_version).to eq("1.0.0")
    end

    it "increments patch version on publish (1.0.0 → 1.0.1)" do
      profile = create(:profile_document,
                       lifecycle_status: "in_progress",
                       metadata_extra: valid_metadata,
                       control_catalog: catalog,
                       profile_version: "1.0.0")
      patch publish_profile_document_path(profile)
      expect(profile.reload.profile_version).to eq("1.0.1")
    end

    it "increments CDEF version on publish" do
      cdef = create(:cdef_document,
                    lifecycle_status: "in_progress",
                    metadata_extra: valid_metadata,
                    cdef_version: "2.1.3")
      patch publish_cdef_document_path(cdef)
      expect(cdef.reload.cdef_version).to eq("2.1.4")
    end

    it "sets CDEF version to 1.0.0 when blank" do
      cdef = create(:cdef_document,
                    lifecycle_status: "in_progress",
                    metadata_extra: valid_metadata,
                    cdef_version: nil)
      patch publish_cdef_document_path(cdef)
      expect(cdef.reload.cdef_version).to eq("1.0.0")
    end

    it "leaves free-text version unchanged" do
      cdef = create(:cdef_document,
                    lifecycle_status: "in_progress",
                    metadata_extra: valid_metadata,
                    cdef_version: "Rev 5 Draft")
      patch publish_cdef_document_path(cdef)
      expect(cdef.reload.cdef_version).to eq("Rev 5 Draft")
    end

    it "includes version in flash success message" do
      cdef = create(:cdef_document,
                    lifecycle_status: "in_progress",
                    metadata_extra: valid_metadata,
                    cdef_version: nil)
      patch publish_cdef_document_path(cdef)
      expect(flash[:success]).to include("version 1.0.0")
    end
  end

  # ── Auto-Priority Assignment (#175) ──────────────────────────────────

  describe "Auto-priority assignment on create_from_catalog" do
    let(:catalog) { create(:control_catalog) }
    let(:family) { create(:control_family, control_catalog: catalog) }

    it "assigns P1 to controls with explicit P1 priority" do
      cc = create(:catalog_control, control_family: family, control_id: "ac-1",
                  priority: "P1", baseline_impact: "LOW")
      post create_from_catalog_profile_documents_path, params: {
        catalog_id: catalog.slug,
        control_ids: [ cc.control_id ],
        baseline_level: "LOW",
        profile_name: "Test Auto-Priority"
      }
      profile = ProfileDocument.order(created_at: :desc).first
      ctrl = profile.profile_controls.find_by(control_id: "ac-1")
      expect(ctrl.priority).to eq("P1")
    end

    it "assigns priority based on baseline breadth when no explicit priority" do
      cc = create(:catalog_control, control_family: family, control_id: "ac-2",
                  priority: nil, baseline_impact: "LOW, MODERATE, HIGH")
      post create_from_catalog_profile_documents_path, params: {
        catalog_id: catalog.slug,
        control_ids: [ cc.control_id ],
        baseline_level: "LOW",
        profile_name: "Test Breadth Priority"
      }
      profile = ProfileDocument.order(created_at: :desc).first
      ctrl = profile.profile_controls.find_by(control_id: "ac-2")
      expect(ctrl.priority).to eq("P1")
    end
  end

  # ── Profile-from-Profile Creation (#175) ──────────────────────────────

  describe "Profile-from-Profile creation" do
    let(:catalog) { create(:control_catalog) }
    let(:source_profile) do
      create(:profile_document,
             lifecycle_status: "published",
             metadata_extra: valid_metadata,
             control_catalog: catalog)
    end

    before do
      source_profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
    end

    it "creates a tailored profile from a published profile" do
      post create_from_profile_profile_documents_path, params: {
        source_profile_id: source_profile.slug,
        profile_name: "Tailored Profile"
      }
      copy = ProfileDocument.order(created_at: :desc).first
      expect(copy.name).to eq("Tailored Profile")
      expect(copy.source_profile).to eq(source_profile)
      expect(copy.lifecycle_status).to eq("in_progress")
      expect(copy.profile_controls.count).to eq(source_profile.profile_controls.count)
    end

    it "rejects creating from an unpublished profile" do
      source_profile.update!(lifecycle_status: "in_progress")
      post create_from_profile_profile_documents_path, params: {
        source_profile_id: source_profile.slug,
        profile_name: "Should Fail"
      }
      expect(flash[:error]).to include("published")
    end

    it "tracks source_profile lineage in derived profile" do
      post create_from_profile_profile_documents_path, params: {
        source_profile_id: source_profile.slug
      }
      copy = ProfileDocument.order(created_at: :desc).first
      expect(copy.source_profile_id).to eq(source_profile.id)
      expect(source_profile.derived_profiles).to include(copy)
    end
  end

  # ── Parameter Completeness Check (#175) ──────────────────────────────

  describe "Parameter completeness check in publish_check" do
    let(:catalog) { create(:control_catalog) }
    let(:profile) do
      create(:profile_document,
             lifecycle_status: "in_progress",
             metadata_extra: valid_metadata,
             control_catalog: catalog)
    end

    it "returns parameters_customized: true when no params exist" do
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
      get publish_check_profile_document_path(profile)
      json = JSON.parse(response.body)
      expect(json["checks"]["parameters_customized"]).to be true
    end

    it "returns parameters_customized: false when params match defaults" do
      ctrl = profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
      ctrl.profile_control_fields.create!(field_name: "parameter:ac-1_prm_1", field_value: "default label")
      ctrl.profile_control_fields.create!(field_name: "parameter_label:ac-1_prm_1", field_value: "default label")
      get publish_check_profile_document_path(profile)
      json = JSON.parse(response.body)
      expect(json["checks"]["parameters_customized"]).to be false
      expect(json["errors"]).to include(match(/default catalog values/))
    end

    it "returns parameters_customized: true when params are customized" do
      ctrl = profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
      ctrl.profile_control_fields.create!(field_name: "parameter:ac-1_prm_1", field_value: "custom value")
      ctrl.profile_control_fields.create!(field_name: "parameter_label:ac-1_prm_1", field_value: "default label")
      get publish_check_profile_document_path(profile)
      json = JSON.parse(response.body)
      expect(json["checks"]["parameters_customized"]).to be true
    end
  end

  # ── OSCAL Back-Matter References (#175) ──────────────────────────────

  describe "OSCAL export back-matter references" do
    let(:catalog) { create(:control_catalog, oscal_uuid: SecureRandom.uuid) }
    let(:profile) do
      create(:profile_document,
             lifecycle_status: "in_progress",
             metadata_extra: valid_metadata,
             control_catalog: catalog)
    end

    it "includes catalog oscal_uuid in profile export imports href" do
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
      service = OscalProfileExportService.new(profile)
      json = JSON.parse(service.export_unvalidated)
      href = json.dig("profile", "imports", 0, "href")
      # #395 P2: profile imports now emit `uuid:<...>` for round-trip
      # stability. The legacy `#<uuid>` anchor form is the fallback.
      expect(href).to eq("uuid:#{catalog.oscal_uuid}")
    end

    it "includes catalog resource in profile export back-matter" do
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")
      service = OscalProfileExportService.new(profile)
      json = JSON.parse(service.export_unvalidated)
      resources = json.dig("profile", "back-matter", "resources")
      catalog_resource = resources.find { |r| r["uuid"] == catalog.oscal_uuid }
      expect(catalog_resource).to be_present
      expect(catalog_resource["title"]).to eq(catalog.name)
    end

    it "includes source profile and catalog in resolved catalog back-matter" do
      family = create(:control_family, control_catalog: catalog)
      create(:catalog_control, control_family: family, control_id: "ac-1", priority: "P1")
      profile.profile_controls.create!(control_id: "ac-1", title: "AC-1", priority: "P1")

      service = OscalResolvedProfileCatalogService.new(profile)
      json = JSON.parse(service.export)
      resources = json.dig("catalog", "back-matter", "resources")
      expect(resources.find { |r| r["uuid"] == profile.uuid }).to be_present
      expect(resources.find { |r| r["uuid"] == catalog.oscal_uuid }).to be_present
    end
  end

  # ── Copy → Republish Lifecycle ──────────────────────────────────────

  describe "Copy and republish lifecycle" do
    let(:catalog) { create(:control_catalog) }

    it "copies a published profile to an editable draft" do
      profile = create(:profile_document,
                       lifecycle_status: "in_progress",
                       metadata_extra: valid_metadata,
                       control_catalog: catalog,
                       profile_version: "1.0.0")
      patch publish_profile_document_path(profile)
      profile.reload
      expect(profile.lifecycle_status).to eq("published")

      post copy_profile_document_path(profile)
      copy = ProfileDocument.order(created_at: :desc).first
      expect(copy.lifecycle_status).to eq("in_progress")
      expect(copy.slug).not_to eq(profile.slug)
      expect(copy.name).to include("Copy of")
    end

    it "copies a published CDEF to an editable draft" do
      cdef = create(:cdef_document,
                    lifecycle_status: "in_progress",
                    metadata_extra: valid_metadata,
                    cdef_version: "1.0.0")
      patch publish_cdef_document_path(cdef)
      cdef.reload
      expect(cdef.lifecycle_status).to eq("published")

      post copy_cdef_document_path(cdef)
      copy = CdefDocument.order(created_at: :desc).first
      expect(copy.lifecycle_status).to eq("in_progress")
      expect(copy.slug).not_to eq(cdef.slug)
    end
  end
end
