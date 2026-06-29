# frozen_string_literal: true

require "rails_helper"

# Issue #672 — the `q` free-text search param on Api::V1 index endpoints. All
# eight artifact indexes share the Searchable.search_text scope; these specs
# exercise it through both wiring paths: the shared DocumentBaseController#index
# (SSP) and a standalone index action (CDEF).
RSpec.describe "Api::V1 index search (?q)", type: :request do
  let(:admin)        { create(:user, :admin) }
  let(:api_token)    { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:boundary)     { create(:authorization_boundary) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def body_data(res) = JSON.parse(res.body)["data"]
  def body_meta(res) = JSON.parse(res.body)["meta"]

  describe "shared DocumentBaseController endpoint (SSP)" do
    it "matches by name (case-insensitive)" do
      create(:ssp_document, name: "Production Portal", authorization_boundary: boundary)
      create(:ssp_document, name: "Dev Sandbox", authorization_boundary: boundary)

      get api_v1_ssp_documents_path, params: { q: "production" }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(body_data(response).map { |d| d["name"] }).to eq([ "Production Portal" ])
    end

    it "matches by description" do
      create(:ssp_document, name: "Alpha", description: "handles cardholder data", authorization_boundary: boundary)
      create(:ssp_document, name: "Beta", description: "internal tooling", authorization_boundary: boundary)

      get api_v1_ssp_documents_path, params: { q: "cardholder" }, headers: auth_headers
      expect(body_data(response).map { |d| d["name"] }).to eq([ "Alpha" ])
    end

    it "returns empty data + zero count on no match" do
      create(:ssp_document, name: "Alpha", authorization_boundary: boundary)

      get api_v1_ssp_documents_path, params: { q: "no-such-thing" }, headers: auth_headers
      expect(body_data(response)).to eq([])
      expect(body_meta(response)["count"]).to eq(0)
    end

    it "composes with pagination" do
      create_list(:ssp_document, 6, name: "Searchable Doc", authorization_boundary: boundary)
      create(:ssp_document, name: "Other", authorization_boundary: boundary)

      get api_v1_ssp_documents_path, params: { q: "searchable", items: 2 }, headers: auth_headers
      expect(body_data(response).length).to eq(2)
      expect(body_meta(response)["count"]).to eq(6)
      expect(body_meta(response)["items"]).to eq(2)
    end

    it "composes with the status filter" do
      create(:ssp_document, name: "Match A", status: "completed", authorization_boundary: boundary)
      create(:ssp_document, name: "Match B", status: "pending", authorization_boundary: boundary)

      get api_v1_ssp_documents_path, params: { q: "match", status: "completed" }, headers: auth_headers
      expect(body_data(response).map { |d| d["name"] }).to eq([ "Match A" ])
    end
  end

  describe "standalone endpoint (CDEF)" do
    it "matches by name and composes with pagination" do
      create_list(:cdef_document, 3, name: "Widget Component")
      create(:cdef_document, name: "Unrelated Thing")

      get api_v1_cdef_documents_path, params: { q: "widget", items: 2 }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(body_data(response).length).to eq(2)
      expect(body_meta(response)["count"]).to eq(3)
    end

    it "returns empty on no match" do
      create(:cdef_document, name: "Widget Component")

      get api_v1_cdef_documents_path, params: { q: "absent" }, headers: auth_headers
      expect(body_data(response)).to eq([])
    end
  end
end
