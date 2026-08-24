# frozen_string_literal: true

require "rails_helper"

# #1039 — the API path was a SINGULAR `resource`, which is the mechanical reason
# it had no index and no show: Rails does not generate them for one. It is now
# plural with full CRUD, so this surface matches every other resource in the
# system rather than being create-only.
#
# Both directions on every guard: a permission-holding NON-ADMIN must succeed,
# and a user without the permission must be refused.
RSpec.describe "Api::V1::AuthoritativeSources CRUD (#1039)", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:writer) { create(:user) }
  let(:reader) { create(:user) }

  let!(:source) do
    create(:back_matter_resource, title: "NIST SP 800-53 Rev 5",
                                  href: "https://csrc.nist.gov/",
                                  globally_available: true)
  end

  def auth(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: "spec-#{SecureRandom.hex(3)}").plaintext_token}" }
  end

  def body = JSON.parse(response.body)

  describe "GET /api/v1/authoritative_sources" do
    it "lists sources — the endpoint that did not exist before" do
      get "/api/v1/authoritative_sources", headers: auth(reader)

      expect(response).to have_http_status(:ok)
      expect(body["data"].map { |d| d["title"] }).to include("NIST SP 800-53 Rev 5")
    end

    it "hides archived sources unless asked" do
      source.update!(archived_at: Time.current)

      get "/api/v1/authoritative_sources", headers: auth(reader)
      expect(body["data"]).to be_empty

      get "/api/v1/authoritative_sources", params: { include_archived: true }, headers: auth(reader)
      expect(body["data"].map { |d| d["id"] }).to include(source.id)
    end
  end

  describe "GET /api/v1/authoritative_sources/:id" do
    it "carries the provenance and dates the contract now promises" do
      source.update!(provided_by_team: "Platform Security", provided_by_contact: "soc@agency.gov")

      get "/api/v1/authoritative_sources/#{source.id}", headers: auth(reader)

      expect(response).to have_http_status(:ok)
      expect(body["data"]).to include(
        "provided_by_team" => "Platform Security",
        "provided_by_contact" => "soc@agency.gov"
      )
      expect(body["data"]["created_at"]).to be_present
      expect(body["data"]["updated_at"]).to be_present
    end
  end

  describe "PATCH /api/v1/authoritative_sources/:id" do
    it "lets a permission-holding non-admin update" do
      grant_permission(writer, "back_matter.write")

      patch "/api/v1/authoritative_sources/#{source.id}",
            params: { back_matter_resource: { provided_by_team: "Platform Security" } },
            headers: auth(writer)

      expect(response).to have_http_status(:ok)
      expect(source.reload.provided_by_team).to eq("Platform Security")
    end

    it "refuses a caller without back_matter.write" do
      patch "/api/v1/authoritative_sources/#{source.id}",
            params: { back_matter_resource: { provided_by_team: "nope" } },
            headers: auth(reader)

      expect(response).to have_http_status(:forbidden)
      expect(source.reload.provided_by_team).to be_nil
    end
  end

  describe "DELETE /api/v1/authoritative_sources/:id" do
    # A DELETE that does not delete is exactly the contract surprise the #995
    # sweep exists to catch, so it returns the archived record rather than a
    # bare 204 and the endpoint page says so.
    it "ARCHIVES and returns the record, rather than deleting it" do
      grant_permission(writer, "back_matter.write")

      expect {
        delete "/api/v1/authoritative_sources/#{source.id}", headers: auth(writer)
      }.not_to change(BackMatterResource, :count)

      expect(response).to have_http_status(:ok)
      expect(body["archived"]).to be(true)
      expect(body["data"]["id"]).to eq(source.id)
      expect(source.reload.archived?).to be(true)
    end

    it "restores" do
      grant_permission(writer, "back_matter.write")
      source.update!(archived_at: Time.current)

      post "/api/v1/authoritative_sources/#{source.id}/restore", headers: auth(writer)

      expect(response).to have_http_status(:ok)
      expect(body["archived"]).to be(false)
      expect(source.reload.archived?).to be(false)
    end

    it "refuses a caller without back_matter.write" do
      delete "/api/v1/authoritative_sources/#{source.id}", headers: auth(reader)

      expect(response).to have_http_status(:forbidden)
      expect(source.reload.archived?).to be(false)
    end
  end
  # A strict allowlist that knows a field only on `update` rejects the create
  # that the web form actually sends. Both verbs, or the field is unusable.
  describe "provenance on create" do
    it "accepts provided_by_team and provided_by_contact when creating" do
      post "/api/v1/authoritative_sources",
           params: { back_matter_resource: {
             title: "NIST SP 800-53 Rev 5",
             href: "https://csrc.nist.gov/",
             provided_by_team: "Platform Security",
             provided_by_contact: "soc@agency.gov"
           } }.to_json,
           headers: auth(admin).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:created), response.body
      body = JSON.parse(response.body)
      expect(body.dig("data", "provided_by_team")).to eq("Platform Security")
      expect(body.dig("data", "provided_by_contact")).to eq("soc@agency.gov")
    end
  end
end
