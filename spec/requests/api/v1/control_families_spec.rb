# frozen_string_literal: true

require "rails_helper"

# #895 — first slice of the Catalog API. The catalog container had a full API
# while its contents had none: you could create a catalog over the API but not
# put a single family in it.
RSpec.describe "Api::V1::ControlFamilies", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth)  { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  let(:catalog) { create(:control_catalog, name: "NIST 800-53 Rev 5") }
  let!(:family) { create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control") }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def path(cat = catalog) = "/api/v1/control_catalogs/#{cat.oscal_uuid}/control_families"

  # The identifier decision recorded on #895: uuid is the stable identity, but
  # slug and numeric id keep resolving so nothing already written breaks.
  describe "catalog identifier" do
    it "accepts the uuid" do
      get path, headers: auth
      expect(response).to have_http_status(:ok)
    end

    it "accepts the slug" do
      get "/api/v1/control_catalogs/#{catalog.slug}/control_families", headers: auth
      expect(response).to have_http_status(:ok)
    end

    it "accepts the numeric id" do
      get "/api/v1/control_catalogs/#{catalog.id}/control_families", headers: auth
      expect(response).to have_http_status(:ok)
    end

    it "404s on an unknown catalog rather than leaking another one" do
      get "/api/v1/control_catalogs/does-not-exist/control_families", headers: auth
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET index" do
    it "lists the catalog's families" do
      get path, headers: auth

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].map { |f| f["code"] }).to include("AC")
      expect(body["meta"]).to include("page", "count")
    end

    it "does not leak families from another catalog" do
      other = create(:control_catalog)
      create(:control_family, control_catalog: other, code: "ZZ", name: "Elsewhere")

      get path, headers: auth

      expect(JSON.parse(response.body)["data"].map { |f| f["code"] }).not_to include("ZZ")
    end
  end

  describe "GET show" do
    it "addresses a family by code, case-insensitively" do
      get "#{path}/ac", headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["name"]).to eq("Access Control")
    end

    it "404s for a code in a different catalog" do
      other = create(:control_catalog)
      create(:control_family, control_catalog: other, code: "ZZ", name: "Elsewhere")

      get "#{path}/zz", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create" do
    it "creates a family and audits it" do
      expect {
        post path, headers: auth, params: {
          control_family: { code: "AU", name: "Audit and Accountability", sort_order: 2 }
        }
      }.to change { catalog.control_families.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["code"]).to eq("AU")
      expect(AuditEvent.where(action: "api_control_family_created")).to exist
    end

    it "refuses a duplicate code in the same catalog" do
      post path, headers: auth, params: { control_family: { code: "AC", name: "Dupe" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # The safeguard: a loose hash would let arbitrary keys into a record the
    # OSCAL exporters read. Every permitted field is enumerated.
    it "ignores fields outside the enumerated allowlist" do
      post path, headers: auth, params: {
        control_family: { code: "CM", name: "Config Mgmt", control_catalog_id: 999_999, id: 12_345 }
      }

      expect(response).to have_http_status(:created)
      created = catalog.control_families.find_by(code: "CM")
      expect(created).to be_present
      expect(created.id).not_to eq(12_345)
      expect(created.control_catalog_id).to eq(catalog.id)
    end
  end

  describe "PATCH update" do
    it "updates and audits" do
      patch "#{path}/ac", headers: auth, params: { control_family: { name: "Access Control (revised)" } }

      expect(response).to have_http_status(:ok)
      expect(family.reload.name).to eq("Access Control (revised)")
      expect(AuditEvent.where(action: "api_control_family_updated")).to exist
    end
  end

  describe "DELETE destroy" do
    it "deletes an empty family and audits it" do
      expect {
        delete "#{path}/ac", headers: auth
      }.to change { catalog.control_families.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(AuditEvent.where(action: "api_control_family_deleted")).to exist
    end

    # Deleting a family takes its controls with it, and those controls are
    # referenced by SSP/SAP/SAR content. Refuse rather than cascade silently.
    it "refuses to delete a family that still has controls" do
      family.catalog_controls.create!(control_id: "ac-1", title: "Policy")

      expect {
        delete "#{path}/ac", headers: auth
      }.not_to change { catalog.control_families.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("still has 1 control")
    end
  end

  describe "authentication and authorization" do
    it "refuses an unauthenticated request" do
      get path
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a write without catalogs.write" do
      reader = create(:user)
      reader_token = ApiToken.generate!(user: reader, name: "Reader")

      post path, headers: { "Authorization" => "Bearer #{reader_token.plaintext_token}" },
           params: { control_family: { code: "PE", name: "Physical" } }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
