# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1290 / #1292 — the Boundary filter beside each document list.
#
# The boundary comes ONLY from the URL (owner, revised phase 2 plan): no
# parameter shows every reachable boundary, each option links to its own
# boundary, and nothing is remembered between pages. Asserts the ROWS each
# link shows, that every count equals the rows behind its link, and that a
# boundary the viewer cannot reach is never named or counted.
RSpec.describe "Boundary filter beside the lists (#1292)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:alpha) { create(:authorization_boundary, name: "Alpha ATO") }
  let(:bravo) { create(:authorization_boundary, name: "Bravo ATO") }

  def listed?(doc, path = polymorphic_path(doc)) = response.body.include?(%(href="#{path}"))

  def page = Nokogiri::HTML(response.body)

  def filter = page.at_css("[data-testid=boundary-filter]")

  def option(boundary) = filter.at_css("[data-testid=boundary-filter-option][data-boundary-id='#{boundary.id}']")

  def current_option = filter.at_css("[aria-current=true]")

  def count_in(link) = link.at_css(".sparc-counter").text.to_i

  before do
    allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true)
    sign_in_as(admin)
  end

  {
    ssp:      [ :ssp_document,  "/ssp_documents" ],
    sap:      [ :sap_document,  "/sap_documents" ],
    sar:      [ :sar_document,  "/sar_documents" ],
    poam:     [ :poam_document, "/poam_documents" ],
    evidence: [ :evidence,      "/evidences" ]
  }.each do |type, (factory, path)|
    context "#{type} list" do
      let!(:in_alpha) { create_list(factory, 2, authorization_boundary: alpha) }
      let!(:in_bravo) { create(factory, authorization_boundary: bravo) }
      # Only legacy rows lack a boundary on the per-system types (#952);
      # evidence without one is global evidence.
      let!(:unattached) do
        type == :evidence ? create(factory, authorization_boundary: nil) : create_legacy_orphan(factory)
      end
      let(:all_docs) { in_alpha + [ in_bravo, unattached ] }

      it "shows every boundary with no parameter, with a count per boundary" do
        get path

        expect(all_docs.map { listed?(_1) }).to all(be(true))
        expect(current_option["data-testid"]).to eq("boundary-filter-all")
        expect(count_in(current_option)).to eq(4)
        # #951 — a boundary's evidence includes global evidence.
        global = type == :evidence ? 1 : 0
        expect([ count_in(option(alpha)), count_in(option(bravo)) ]).to eq([ 2 + global, 1 + global ])
        expect(count_in(filter.at_css("[data-testid=boundary-filter-none]"))).to eq(1)
      end

      it "narrows to the boundary each option links to, and each count is the rows behind it" do
        get path
        links = filter.css("a.sparc-filter-link").map { [ _1["href"], count_in(_1), _1.text.squish ] }

        links.each do |href, count, label|
          get href
          expect(all_docs.count { listed?(_1) }).to eq(count), label
          expect(current_option.text.squish).to eq(label)
        end

        get path
        alpha_href = option(alpha)["href"]
        expect(alpha_href).to include("authorization_boundary_id=#{alpha.id}")
        get alpha_href
        expect(in_alpha.map { listed?(_1) }).to all(be(true))
        expect(listed?(in_bravo)).to be(false)
        expect(listed?(unattached)).to be(type == :evidence)
      end

      it "remembers nothing: the next visit without a parameter shows every boundary again" do
        get path, params: { authorization_boundary_id: bravo.id }
        expect(listed?(in_bravo)).to be(true)
        expect(in_alpha.map { listed?(_1) }).to all(be(false))

        get path
        expect(all_docs.map { listed?(_1) }).to all(be(true))
        expect(session.to_h.keys.grep(/boundary/)).to be_empty
      end

      it "reaches documents attached to no boundary" do
        get path, params: { authorization_boundary_id: "none" }

        expect(listed?(unattached)).to be(true)
        expect((in_alpha + [ in_bravo ]).map { listed?(_1) }).to all(be(false))
        expect(current_option["data-testid"]).to eq("boundary-filter-none")
      end
    end
  end

  describe "the list's own filters" do
    let!(:done_alpha) { create(:poam_document, authorization_boundary: alpha, status: "completed") }
    let!(:done_bravo) { create(:poam_document, authorization_boundary: bravo, status: "completed") }

    it "chooses the boundary in one place: no boundary dropdown or chip in the filter row" do
      get "/poam_documents", params: { status: "completed", authorization_boundary_id: alpha.id }

      expect(page.css("select[name=authorization_boundary_id]")).to be_empty
      expect(page.css(".sparc-chip").map { _1.text.squish }.grep(/boundary/i)).to be_empty
      expect(page.text).to include("1 filter active")
    end

    it "keeps the boundary when the filter form is submitted or the filters are cleared" do
      get "/poam_documents", params: { status: "completed", authorization_boundary_id: alpha.id }

      hidden = page.css("form input[type=hidden][name=authorization_boundary_id]").map { _1["value"] }
      expect(hidden).to include(alpha.id.to_s)
      clear = page.css("a").find { |a| a.text.strip == "Clear all" }
      expect(Rack::Utils.parse_query(URI(clear["href"]).query)).to eq("authorization_boundary_id" => alpha.id.to_s)

      get clear["href"]
      expect([ listed?(done_alpha), listed?(done_bravo) ]).to eq([ true, false ])
    end

    it "keeps the other filters when a boundary is chosen" do
      get "/poam_documents", params: { status: "completed", page: 1 }
      query = Rack::Utils.parse_query(URI(option(bravo)["href"]).query)

      expect(query).to eq("status" => "completed", "authorization_boundary_id" => bravo.id.to_s)
    end
  end

  describe "CDEFs: the boundary's own, plus global ones linked to it (#1287, #929)" do
    let!(:own_alpha) do
      create(:cdef_document).tap { |c| CdefScopeService.apply(c, scope: "boundary", authorization_boundary_id: alpha.id) }
    end
    let!(:own_bravo) do
      create(:cdef_document).tap { |c| CdefScopeService.apply(c, scope: "boundary", authorization_boundary_id: bravo.id) }
    end
    let!(:global_linked) do
      create(:cdef_document, globally_available: true).tap do |c|
        create(:boundary_cdef_document, boundary: create(:boundary, authorization_boundary: alpha), cdef_document: c)
      end
    end
    let!(:global_unlinked) { create(:cdef_document, globally_available: true) }

    it "lists Alpha's own CDEF even though Alpha had no environment when it was scoped, and counts it" do
      expect(BoundaryCdefDocument.where(cdef_document: own_alpha)).to be_empty

      get "/cdef_documents", params: { authorization_boundary_id: alpha.id }

      expect([ own_alpha, global_linked ].map { listed?(_1) }).to all(be(true))
      expect([ own_bravo, global_unlinked ].map { listed?(_1) }).to all(be(false))
      expect(count_in(option(alpha))).to eq(2)
      # No unattached CDEFs exist, so "Not attached" is not offered.
      expect(filter.at_css("[data-testid=boundary-filter-none]")).to be_nil
    end

    it "counts a CDEF that has since gone wider as no longer the boundary's own" do
      CdefScopeService.apply(own_alpha, scope: "instance")

      get "/cdef_documents", params: { authorization_boundary_id: alpha.id }
      expect(listed?(own_alpha)).to be(false)
    end
  end

  describe "leveraged POA&Ms follow the boundary that leverages them" do
    let(:provider_one) { create(:authorization_boundary, name: "Provider One") }
    let(:provider_two) { create(:authorization_boundary, name: "Provider Two") }
    let!(:poam_one) { create(:poam_document, authorization_boundary: provider_one) }
    let!(:poam_two) { create(:poam_document, authorization_boundary: provider_two) }

    before do
      create(:leveraged_authorization, leveraging_boundary: alpha, leveraged_boundary: provider_one)
      create(:leveraged_authorization, leveraging_boundary: bravo, leveraged_boundary: provider_two)
    end

    def leveraged_listed = [ poam_one, poam_two ].map { listed?(_1, leveraged_poam_document_path(_1)) }

    it "lists only what the chosen boundary leverages" do
      get "/leveraged_poam_documents"
      expect(leveraged_listed).to eq([ true, true ])
      expect([ count_in(option(alpha)), count_in(option(bravo)) ]).to eq([ 1, 1 ])

      get "/leveraged_poam_documents", params: { authorization_boundary_id: bravo.id }
      expect(leveraged_listed).to eq([ false, true ])
    end
  end

  describe "saved CDEF coverage analyses" do
    let!(:run_alpha) { create(:cdef_coverage_run, authorization_boundary: alpha) }
    let!(:run_bravo) { create(:cdef_coverage_run, authorization_boundary: bravo) }
    let!(:run_none)  { create(:cdef_coverage_run, authorization_boundary: nil) }

    def runs_listed = [ run_alpha, run_bravo, run_none ].map { listed?(_1, cdef_coverage_path(_1)) }

    it "narrow on the web by the filter" do
      get "/cdef_coverage"
      expect(runs_listed).to eq([ true, true, true ])

      get option(alpha)["href"]
      expect(runs_listed).to eq([ true, false, false ])

      get "/cdef_coverage", params: { authorization_boundary_id: "none" }
      expect(runs_listed).to eq([ false, false, true ])
    end

    # Found walking the phase 2 image: the list called `pagy_nav`, which is not
    # a helper here, so a second page of analyses raised a 500 (since #904).
    it "pages like every other list" do
      get "/cdef_coverage", params: { per_page: 2 }
      expect(response).to have_http_status(:ok)
      expect(page.css("output").text).to include("saved analyses")

      get "/cdef_coverage", params: { per_page: 2, page: 2 }
      expect(response).to have_http_status(:ok)
      expect(runs_listed.count(true)).to eq(1)
    end

    it "narrow the same way on the API" do
      token = ApiToken.generate!(user: admin, name: "caller", expires_at: 1.day.from_now)
      headers = { "Authorization" => "Bearer #{token.plaintext_token}" }

      ids = lambda do |params|
        get "/api/v1/cdef_coverage/runs", params: params, headers: headers
        expect(response).to have_http_status(:ok)
        response.parsed_body["data"].map { _1["id"] }
      end

      expect(ids.call(authorization_boundary_id: alpha.id)).to eq([ run_alpha.id ])
      expect(ids.call(authorization_boundary_id: "none")).to eq([ run_none.id ])
      expect(ids.call({})).to match_array([ run_alpha.id, run_bravo.id, run_none.id ])
    end
  end

  describe "a boundary the viewer cannot reach" do
    let(:member) do
      role = create(:role, :authorization_boundary_scoped,
                    permissions: { "authorization_boundaries.read" => true, "ssp.read" => true })
      create(:user).tap { |u| create(:user_role, user: u, role: role, authorization_boundary: alpha) }
    end
    let!(:ssp_alpha) { create(:ssp_document, authorization_boundary: alpha) }
    let!(:ssp_bravo) { create(:ssp_document, authorization_boundary: bravo) }

    before { sign_in_as(member) }

    it "is neither offered nor counted" do
      get "/ssp_documents"

      expect(listed?(ssp_alpha)).to be(true)
      expect(option(bravo)).to be_nil
      expect(count_in(filter.at_css("[data-testid=boundary-filter-all]"))).to eq(1)
      expect(response.body).not_to include("Bravo ATO")
    end

    it "shows nothing when a link names it, says only that it is not available, and never names it" do
      get "/ssp_documents", params: { authorization_boundary_id: bravo.id }
      expect(listed?(ssp_bravo)).to be(false)
      expect(page.at_css("[data-testid=boundary-filter-unavailable]")).to be_present
      expect(response.body).not_to include("Bravo ATO")
      unreachable = filter.to_html

      get "/ssp_documents", params: { authorization_boundary_id: AuthorizationBoundary.maximum(:id) + 1000 }
      # Unreachable and nonexistent read the same (the filter's links never
      # carry the requested id).
      expect(filter.to_html).to eq(unreachable)
    end

    it "shows nothing for a value that is not an id" do
      orphan = create_legacy_orphan(:ssp_document)
      sign_in_as(admin)
      get "/ssp_documents", params: { authorization_boundary_id: "abc" }

      expect([ listed?(ssp_alpha), listed?(ssp_bravo), listed?(orphan) ]).to all(be(false))
      expect(page.at_css("[data-testid=boundary-filter-unavailable]")).to be_present
    end
  end

  it "costs the same number of queries however many boundaries there are" do
    create(:ssp_document, authorization_boundary: alpha)
    # The filter's own cost: the same page with the shell on, minus with it
    # off. (The list itself renders more rows as records are added.)
    filter_cost = lambda do
      %w[on off].map do |state|
        allow(SparcConfig).to receive(:nav_shell?).and_return(state == "on")
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached] }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get "/ssp_documents" }
        queries.size
      end.inject(:-)
    end
    small = filter_cost.call

    5.times { create(:ssp_document, authorization_boundary: create(:authorization_boundary)) }
    expect(filter_cost.call).to eq(small)
    expect(small).to be <= 5
  end

  it "is not offered on a shared-library list" do
    get "/control_catalogs"
    expect(response).to have_http_status(:ok)
    expect(filter).to be_nil
  end

  context "with SPARC_NAV_SHELL off" do
    let!(:in_alpha) { create(:ssp_document, authorization_boundary: alpha) }
    let!(:in_bravo) { create(:ssp_document, authorization_boundary: bravo) }

    before { allow(SparcConfig).to receive(:nav_shell?).and_return(false) }

    it "narrows by the sidebar link as before, with no filter column" do
      get "/ssp_documents", params: { authorization_boundary_id: alpha.id }

      expect([ listed?(in_alpha), listed?(in_bravo) ]).to eq([ true, false ])
      expect(filter).to be_nil
    end
  end
end
