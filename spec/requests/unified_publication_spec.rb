# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Unified publication lifecycle", type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  let(:party_uuid) { SecureRandom.uuid }
  let(:valid_metadata) do
    {
      "roles" => [{ "id" => "prepared-by", "title" => "Prepared By" }],
      "parties" => [{ "uuid" => party_uuid, "type" => "organization", "name" => "Test Org" }],
      "responsible-parties" => [{ "role-id" => "prepared-by", "party-uuids" => [party_uuid] }]
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
          roles: [{ "id" => "prepared-by", "title" => "Prepared By" }].to_json,
          parties: [{ "uuid" => party_uuid, "type" => "organization", "name" => "Fix Org" }].to_json,
          responsible_parties: [{ "role-id" => "prepared-by", "party-uuids" => [party_uuid] }].to_json
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
