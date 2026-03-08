# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ControlFamilies", type: :request do
  let(:catalog_write_role) do
    create(:role, name: "policy_manager", scope: "instance",
           permissions: { "catalogs.write" => true })
  end
  let(:user) do
    u = create(:user, password: "SecurePassword123!", password_confirmation: "SecurePassword123!")
    create(:user_role, user: u, role: catalog_write_role)
    u
  end
  let(:catalog) { create(:control_catalog) }

  before { sign_in(user) }

  describe "GET /control_families/:id" do
    it "shows the family with its controls" do
      family = create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control")
      family.catalog_controls.create!(control_id: "AC-01", title: "Access Policy")

      get control_family_path(family)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("AC")
      expect(response.body).to include("Access Control")
      expect(response.body).to include("AC-01")
    end
  end

  describe "GET /control_catalogs/:id/control_families/new" do
    it "renders the new family form" do
      get new_control_catalog_control_family_path(catalog)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add Family")
    end
  end

  describe "POST /control_catalogs/:id/control_families" do
    it "creates a new family with valid params" do
      expect {
        post control_catalog_control_families_path(catalog), params: {
          control_family: { code: "AC", name: "Access Control", description: "Controls access" }
        }
      }.to change(ControlFamily, :count).by(1)

      family = ControlFamily.last
      expect(family.code).to eq("AC")
      expect(family.name).to eq("Access Control")
      expect(response).to redirect_to(control_family_path(family))
    end

    it "normalizes code to uppercase" do
      post control_catalog_control_families_path(catalog), params: {
        control_family: { code: "ac", name: "Access Control" }
      }

      expect(ControlFamily.last.code).to eq("AC")
    end

    it "auto-assigns sort_order" do
      post control_catalog_control_families_path(catalog), params: {
        control_family: { code: "AC", name: "Access Control" }
      }

      expect(ControlFamily.last.sort_order).to eq(1)
    end

    it "rejects duplicate code in same catalog" do
      create(:control_family, control_catalog: catalog, code: "AC")

      expect {
        post control_catalog_control_families_path(catalog), params: {
          control_family: { code: "AC", name: "Duplicate" }
        }
      }.not_to change(ControlFamily, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects blank name" do
      expect {
        post control_catalog_control_families_path(catalog), params: {
          control_family: { code: "AC", name: "" }
        }
      }.not_to change(ControlFamily, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects invalid code format" do
      expect {
        post control_catalog_control_families_path(catalog), params: {
          control_family: { code: "A1", name: "Bad Code" }
        }
      }.not_to change(ControlFamily, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /control_families/:id/edit" do
    it "renders the edit form" do
      family = create(:control_family, control_catalog: catalog, code: "AC")
      get edit_control_family_path(family)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("AC")
    end
  end

  describe "PATCH /control_families/:id" do
    it "updates the family" do
      family = create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control")

      patch control_family_path(family), params: {
        control_family: { name: "Updated Access Control" }
      }

      expect(response).to redirect_to(control_family_path(family))
      expect(family.reload.name).to eq("Updated Access Control")
    end
  end

  describe "DELETE /control_families/:id" do
    it "deletes the family and redirects to catalog" do
      family = create(:control_family, control_catalog: catalog, code: "AC")

      expect {
        delete control_family_path(family)
      }.to change(ControlFamily, :count).by(-1)

      expect(response).to redirect_to(control_catalog_path(catalog))
    end

    it "cascades deletion to catalog controls" do
      family = create(:control_family, control_catalog: catalog, code: "AC")
      family.catalog_controls.create!(control_id: "AC-01", title: "Test")

      expect {
        delete control_family_path(family)
      }.to change(CatalogControl, :count).by(-1)
    end
  end
end
