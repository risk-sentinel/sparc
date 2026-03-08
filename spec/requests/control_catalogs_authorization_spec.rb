# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog Authorization", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog) }

  let(:policy_manager_role) do
    create(:role, name: "policy_manager", scope: "instance",
           permissions: { "catalogs.read" => true, "catalogs.write" => true })
  end

  let(:viewer_role) do
    create(:role, name: "global_viewer", scope: "instance",
           permissions: { "catalogs.read" => true })
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

  # ── ControlCatalogsController ──────────────────────────────────────────

  describe "ControlCatalogsController" do
    context "read actions (no write permission needed)" do
      it "allows viewer to access index" do
        sign_in_as(viewer_user)
        get control_catalogs_path
        expect(response).to have_http_status(:ok)
      end

      it "allows viewer to access show" do
        sign_in_as(viewer_user)
        get control_catalog_path(catalog)
        expect(response).to have_http_status(:ok)
      end
    end

    context "write actions require catalogs.write" do
      it "redirects viewer from new" do
        sign_in_as(viewer_user)
        get new_control_catalog_path
        expect(response).to redirect_to(root_path)
      end

      it "allows policy manager to access new" do
        sign_in_as(policy_user)
        get new_control_catalog_path
        expect(response).to have_http_status(:ok)
      end

      it "allows admin to access new" do
        sign_in_as(admin)
        get new_control_catalog_path
        expect(response).to have_http_status(:ok)
      end

      it "redirects viewer from edit" do
        sign_in_as(viewer_user)
        get edit_control_catalog_path(catalog)
        expect(response).to redirect_to(root_path)
      end

      it "redirects viewer from create" do
        sign_in_as(viewer_user)
        post control_catalogs_path, params: {
          control_catalog: { name: "Test", template: "blank" }
        }
        expect(response).to redirect_to(root_path)
      end

      it "redirects viewer from destroy" do
        sign_in_as(viewer_user)
        delete control_catalog_path(catalog)
        expect(response).to redirect_to(root_path)
      end

      it "redirects viewer from import" do
        sign_in_as(viewer_user)
        get import_control_catalogs_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  # ── ControlFamiliesController ──────────────────────────────────────────

  describe "ControlFamiliesController" do
    it "allows viewer to access show" do
      sign_in_as(viewer_user)
      get control_family_path(family)
      expect(response).to have_http_status(:ok)
    end

    it "redirects viewer from new" do
      sign_in_as(viewer_user)
      get new_control_catalog_control_family_path(catalog)
      expect(response).to redirect_to(root_path)
    end

    it "allows policy manager to create family" do
      sign_in_as(policy_user)
      post control_catalog_control_families_path(catalog), params: {
        control_family: { code: "ZZ", name: "Test Family" }
      }
      expect(response).to have_http_status(:redirect)
      expect(response).not_to redirect_to(root_path)
    end

    it "redirects viewer from destroy" do
      sign_in_as(viewer_user)
      delete control_family_path(family)
      expect(response).to redirect_to(root_path)
    end
  end

  # ── CatalogControlsController ──────────────────────────────────────────

  describe "CatalogControlsController" do
    it "redirects viewer from new" do
      sign_in_as(viewer_user)
      get new_control_family_catalog_control_path(family)
      expect(response).to redirect_to(root_path)
    end

    it "allows policy manager to access new" do
      sign_in_as(policy_user)
      get new_control_family_catalog_control_path(family)
      expect(response).to have_http_status(:ok)
    end

    it "redirects viewer from batch_new" do
      sign_in_as(viewer_user)
      get batch_new_control_family_catalog_controls_path(family)
      expect(response).to redirect_to(root_path)
    end
  end

  # ── Auth disabled (backward compatibility) ─────────────────────────────

  describe "when auth is disabled" do
    before do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false)
    end

    it "allows any user to access write actions" do
      sign_in_as(viewer_user)
      get new_control_catalog_path
      expect(response).to have_http_status(:ok)
    end
  end
end
