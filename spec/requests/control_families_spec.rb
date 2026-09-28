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
      family.catalog_controls.create!(control_id: "ac-1", label: "AC-1", title: "Access Policy")

      # #881 — the numeric family URL now 301s onto the catalog-scoped,
      # code-addressed one; the page itself is unchanged.
      get control_family_path(family)
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(control_catalog_family_path(catalog.url_id, "ac"))

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("AC")
      expect(response.body).to include("Access Control")
      expect(response.body).to include("AC-1")
    end
  end

  # #1115 — a retired entry is kept for the assessments recorded against it,
  # and must not read as current.
  describe "retired entries" do
    let(:family) { create(:control_family, control_catalog: catalog, code: "IAM", name: "Identity") }

    before do
      family.catalog_controls.create!(control_id: "ksi-iam-elp", label: "KSI-IAM-ELP", title: "Ensuring Least Privilege")
      family.catalog_controls.create!(control_id: "ksi-iam-03", label: "KSI-IAM-03", title: "Centralized Identity",
                                      retired_at: 1.day.ago, superseded_by: [ "KSI-IAM-APM" ])
    end

    it "badges a retired control on the family page, with its successor" do
      get control_catalog_family_path(catalog.url_id, "iam")

      row = Nokogiri::HTML(response.body).css("tr").find { |tr| tr.text.include?("Centralized Identity") }
      expect(row.text).to include("Retired", "Superseded by KSI-IAM-APM")
      current = Nokogiri::HTML(response.body).css("tr").find { |tr| tr.text.include?("Ensuring Least Privilege") }
      expect(current.text).not_to include("Retired")
    end

    it "counts current controls on the catalog page, with the retired ones apart, and badges a retired family" do
      create(:control_family, control_catalog: catalog, code: "AUTH", name: "Authorization by FedRAMP", retired_at: 1.day.ago)

      get control_catalog_path(catalog)
      follow_redirect! while response.redirect?

      rows = Nokogiri::HTML(response.body).css("tbody tr")
      iam = rows.find { |tr| tr.text.include?("Identity") }
      auth = rows.find { |tr| tr.text.include?("Authorization by FedRAMP") }
      expect(iam.text.squish).to include("1 +1 retired")
      expect(iam.text).not_to match(/\bRetired\b/)
      expect(auth.text).to include("Retired")
    end

    # #1193 — a retired theme keeps the sort_order the old seed gave it (AUTH
    # was 1); it must still list after every current family.
    it "lists a retired family after the current ones, whatever its sort_order" do
      family.update!(sort_order: 5)
      create(:control_family, control_catalog: catalog, code: "AUTH", name: "Authorization by FedRAMP",
                              sort_order: 1, retired_at: 1.day.ago)

      get control_catalog_path(catalog)
      follow_redirect! while response.redirect?

      codes = Nokogiri::HTML(response.body).css("tbody tr td:first-child").map { |td| td.text.squish.split.first }
      expect(codes).to eq(%w[IAM AUTH])
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

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects blank name" do
      expect {
        post control_catalog_control_families_path(catalog), params: {
          control_family: { code: "AC", name: "" }
        }
      }.not_to change(ControlFamily, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects invalid code format" do
      expect {
        post control_catalog_control_families_path(catalog), params: {
          control_family: { code: "1BAD", name: "Bad Code" }
        }
      }.not_to change(ControlFamily, :count)

      expect(response).to have_http_status(:unprocessable_content)
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
      family.catalog_controls.create!(control_id: "ac-1", title: "Test")

      expect {
        delete control_family_path(family)
      }.to change(CatalogControl, :count).by(-1)
    end
  end
end
