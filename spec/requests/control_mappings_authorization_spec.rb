# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Control Mappings Authorization", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:source_catalog) { create(:control_catalog) }
  let(:target_catalog) { create(:control_catalog) }
  let(:mapping) do
    create(:control_mapping, source_catalog: source_catalog, target_catalog: target_catalog)
  end

  let(:policy_manager_role) do
    create(:role, name: "policy_manager", scope: "instance",
           permissions: { "mappings.read" => true, "mappings.write" => true })
  end

  let(:viewer_role) do
    create(:role, name: "global_viewer", scope: "instance",
           permissions: { "mappings.read" => true })
  end

  let(:policy_user) do
    user = create(:user)
    create(:user_role, user: user, role: policy_manager_role)
    user
  end

  let(:viewer_user) do
    user = create(:user)
    create(:user_role, user: user, role: viewer_role)
    user
  end

  # ── Read Actions ───────────────────────────────────────────────────────

  describe "read actions" do
    it "allows viewer to access index" do
      sign_in_as(viewer_user)
      get control_mappings_path
      expect(response).to have_http_status(:ok)
    end

    it "allows viewer to access show" do
      sign_in_as(viewer_user)
      get control_mapping_path(mapping)
      expect(response).to have_http_status(:ok)
    end

    it "allows viewer to download OSCAL export" do
      sign_in_as(viewer_user)
      get download_oscal_control_mapping_path(mapping)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  # ── Write Actions ──────────────────────────────────────────────────────

  describe "write actions require mappings.write" do
    it "redirects viewer from new" do
      sign_in_as(viewer_user)
      get new_control_mapping_path
      expect(response).to redirect_to(root_path)
    end

    it "redirects viewer from create" do
      sign_in_as(viewer_user)
      post control_mappings_path, params: {
        control_mapping: { name: "Test", source_catalog_id: source_catalog.id,
                           target_catalog_id: target_catalog.id }
      }
      expect(response).to redirect_to(root_path)
    end

    it "redirects viewer from edit" do
      sign_in_as(viewer_user)
      get edit_control_mapping_path(mapping)
      expect(response).to redirect_to(root_path)
    end

    it "redirects viewer from destroy" do
      sign_in_as(viewer_user)
      delete control_mapping_path(mapping)
      expect(response).to redirect_to(root_path)
    end

    it "allows policy manager to access new" do
      sign_in_as(policy_user)
      get new_control_mapping_path
      expect(response).to have_http_status(:ok)
    end

    it "allows policy manager to create" do
      sign_in_as(policy_user)
      post control_mappings_path, params: {
        control_mapping: { name: "New Mapping", source_catalog_id: source_catalog.id,
                           target_catalog_id: target_catalog.id }
      }
      expect(response).to have_http_status(:redirect)
      expect(ControlMapping.last.name).to eq("New Mapping")
    end

    it "allows policy manager to publish" do
      sign_in_as(policy_user)
      patch publish_control_mapping_path(mapping)
      expect(mapping.reload.status).to eq("complete")
    end

    it "allows policy manager to deprecate" do
      mapping.update!(status: "complete")
      sign_in_as(policy_user)
      patch deprecate_control_mapping_path(mapping)
      expect(mapping.reload.status).to eq("deprecated")
    end
  end

  # ── Entry Management ───────────────────────────────────────────────────

  describe "entry management" do
    it "redirects viewer from creating an entry" do
      sign_in_as(viewer_user)
      post control_mapping_entries_path(mapping), params: {
        control_mapping_entry: { source_control_id: "AC-1", target_control_id: "A.5.1",
                                  relationship: "equivalent" }
      }
      expect(response).to redirect_to(root_path)
    end

    it "allows policy manager to add an entry" do
      sign_in_as(policy_user)
      post control_mapping_entries_path(mapping), params: {
        control_mapping_entry: { source_control_id: "AC-1", target_control_id: "A.5.1",
                                  relationship: "equivalent" }
      }
      expect(response).to redirect_to(control_mapping_path(mapping))
      expect(mapping.control_mapping_entries.count).to eq(1)
    end
  end

  # ── Auth Disabled ──────────────────────────────────────────────────────

  describe "when auth is disabled" do
    before do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false)
    end

    it "allows any user to access write actions" do
      sign_in_as(viewer_user)
      get new_control_mapping_path
      expect(response).to have_http_status(:ok)
    end
  end
end
