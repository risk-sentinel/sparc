# frozen_string_literal: true

require "rails_helper"

# #1202 — choosing a boundary in the sidebar lists THAT boundary's documents.
#
# The sidebar has linked every document list with `?authorization_boundary_id=`,
# and the SSP, SAP and SAR lists never read it: both boundaries showed the same
# rows. #951 had already found and fixed exactly this for CDEFs alone. What was
# missing was one definition the sidebar link, the web list and Api::V1 all read,
# so this spec asserts the ROWS (not the link's href, which is what let it pass
# before) for every type in that definition, in both directions.
RSpec.describe "Boundary-scoped document lists (#1202)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:boundary_a) { create(:authorization_boundary, name: "Alpha ATO") }
  let(:boundary_b) { create(:authorization_boundary, name: "Bravo ATO") }

  # Two per boundary: a boundary holds many of each (#1203), and a rule that
  # returned only one would pass a one-document fixture. A local, not a
  # constant: a constant here would be defined at the top level and leak.
  column_types = {
    ssp:  [ :ssp_document,  "/ssp_documents" ],
    sap:  [ :sap_document,  "/sap_documents" ],
    sar:  [ :sar_document,  "/sar_documents" ],
    poam: [ :poam_document, "/poam_documents" ]
  }.freeze

  def docs_for(factory, boundary)
    create_list(factory, 2, authorization_boundary: boundary)
  end

  def listed?(doc) = response.body.include?(%(href="#{polymorphic_path(doc)}"))

  describe "every column-owned type narrows to the chosen boundary" do
    before { sign_in_as(admin) }

    column_types.each do |type, (factory, path)|
      context type.to_s do
        let!(:in_a) { docs_for(factory, boundary_a) }
        let!(:in_b) { docs_for(factory, boundary_b) }

        it "lists every one of A's documents and none of B's" do
          get path, params: { authorization_boundary_id: boundary_a.id }

          expect(response).to have_http_status(:ok)
          expect(in_a).to all(satisfy { |d| listed?(d) })
          expect(in_b).to all(satisfy { |d| !listed?(d) })
        end

        it "lists every one of B's documents and none of A's" do
          get path, params: { authorization_boundary_id: boundary_b.id }

          expect(in_b).to all(satisfy { |d| listed?(d) })
          expect(in_a).to all(satisfy { |d| !listed?(d) })
        end

        it "lists both boundaries' documents when no boundary is chosen" do
          get path

          expect(in_a + in_b).to all(satisfy { |d| listed?(d) })
        end
      end
    end
  end

  describe "evidence (#951: a boundary's list includes global evidence)" do
    before { sign_in_as(admin) }

    let!(:in_a)   { create(:evidence, authorization_boundary: boundary_a) }
    let!(:in_b)   { create(:evidence, authorization_boundary: boundary_b) }
    let!(:global) { create(:evidence, authorization_boundary: nil) }

    it "shows A's and the global evidence under A, and never B's" do
      get "/evidences", params: { authorization_boundary_id: boundary_a.id }

      expect(listed?(in_a)).to be(true)
      expect(listed?(global)).to be(true)
      expect(listed?(in_b)).to be(false)
    end
  end

  describe "CDEFs (#951: the ones the boundary uses)" do
    before { sign_in_as(admin) }

    let!(:used_by_a) { create(:cdef_document) }
    let!(:used_by_b) { create(:cdef_document) }

    before do
      create(:boundary_cdef_document, boundary: create(:boundary, authorization_boundary: boundary_a), cdef_document: used_by_a)
      create(:boundary_cdef_document, boundary: create(:boundary, authorization_boundary: boundary_b), cdef_document: used_by_b)
    end

    it "lists A's CDEF and not B's" do
      get "/cdef_documents", params: { authorization_boundary_id: boundary_a.id }

      expect(listed?(used_by_a)).to be(true)
      expect(listed?(used_by_b)).to be(false)
    end
  end

  describe "it narrows what the user may see; it never widens it" do
    let(:member_of_a) { create(:user) }
    let!(:ssps_a) { docs_for(:ssp_document, boundary_a) }
    let!(:ssps_b) { docs_for(:ssp_document, boundary_b) }

    before do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      grant_permission(member_of_a, "ssp.read", authorization_boundary: boundary_a)
      sign_in_as(member_of_a)
    end

    it "shows none of B's documents to a user who cannot see B, even when B is asked for" do
      get "/ssp_documents", params: { authorization_boundary_id: boundary_b.id }

      expect(response).to have_http_status(:ok)
      expect(ssps_b).to all(satisfy { |d| !listed?(d) })
      expect(ssps_a).to all(satisfy { |d| !listed?(d) })
    end

    it "shows that user their own boundary's documents" do
      get "/ssp_documents", params: { authorization_boundary_id: boundary_a.id }

      expect(ssps_a).to all(satisfy { |d| listed?(d) })
    end
  end

  describe "the web list and Api::V1 return the same documents" do
    let(:token) { ApiToken.generate!(user: admin, name: "spec-1202") }
    let(:headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }

    column_types.each do |type, (factory, path)|
      it "agrees for #{type}" do
        in_a = docs_for(factory, boundary_a)
        docs_for(factory, boundary_b)

        get "/api/v1#{path}", params: { authorization_boundary_id: boundary_a.id }, headers: headers
        api_slugs = response.parsed_body.fetch("data").map { |d| d["slug"] }

        sign_in_as(admin)
        get path, params: { authorization_boundary_id: boundary_a.id }
        web_slugs = (in_a + (factory.to_s.classify.constantize.all - in_a)).select { |d| listed?(d) }.map(&:slug)

        expect(api_slugs).to match_array(in_a.map(&:slug))
        expect(web_slugs).to match_array(api_slugs)
      end
    end
  end

  describe "the sidebar links come from the same definition" do
    before { sign_in_as(admin) }

    it "links each document type to its boundary-scoped list, exactly as before" do
      # The sidebar lists boundaries under their organization.
      boundary_a.update!(organization: create(:organization))
      get "/"

      {
        cdef: "/cdef_documents", ssp: "/ssp_documents", sap: "/sap_documents",
        evidence: "/evidences", sar: "/sar_documents", poam: "/poam_documents"
      }.each do |type, list|
        expected = "#{list}?authorization_boundary_id=#{boundary_a.id}"
        expect(BoundaryScopedList.path(type, boundary_a)).to eq(expected)
        expect(response.body).to include(%(href="#{expected}"))
      end
    end

    it "covers every type the definition knows, so a new list cannot be left out" do
      expect(BoundaryScopedList.types).to contain_exactly(:cdef, :ssp, :sap, :evidence, :sar, :poam)
    end
  end
end
