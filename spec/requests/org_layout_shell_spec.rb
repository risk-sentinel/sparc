# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf — the organization layout behind SPARC_NAV_SHELL (owner,
# 2026-10-29): the organization and boundary tab bars, the Overview home and
# the Boundaries tab. Asserts what each viewer is OFFERED and that every count
# equals what its list shows, in both directions (an admin sees the admin tabs,
# a member does not; a member's counts never include a boundary they cannot
# reach).
RSpec.describe "Organization layout (1.18.0-rf)", type: :request do
  let(:alpha) { create(:authorization_boundary, name: "Alpha ATO", status: "active") }
  let(:bravo) { create(:authorization_boundary, name: "Bravo ATO", status: "draft") }
  let(:hidden) { create(:authorization_boundary, name: "Hidden ATO", status: "active") }
  let(:admin) { create(:user, :admin) }
  let(:member_role) do
    perms = %w[authorization_boundaries ssp sap sar poam evidence cdef].to_h { [ "#{_1}.read", true ] }
    create(:role, :authorization_boundary_scoped, permissions: perms)
  end
  let(:member) do
    create(:user).tap { |u| [ alpha, bravo ].each { create(:user_role, user: u, role: member_role, authorization_boundary: _1) } }
  end

  def page = Nokogiri::HTML(response.body)

  def tabs(testid) = page.css("[data-testid=#{testid}] [data-testid=shell-tab]")

  def tab_keys(testid) = tabs(testid).map { _1["data-tab"].to_sym }

  def tab_counts(testid)
    tabs(testid).to_h { [ _1["data-tab"].to_sym, _1.at_css(".sparc-counter")&.text&.delete(",")&.to_i ] }.compact
  end

  def current_tab(testid) = page.at_css("[data-testid=#{testid}] [aria-current=page]")&.[]("data-tab")&.to_sym

  before do
    allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true)
    [ alpha, bravo, hidden ].each do |b|
      create(:ssp_document, authorization_boundary: b)
      create_list(:poam_document, 2, authorization_boundary: b)
    end
  end

  describe "the organization tab bar" do
    it "offers an administrator every tab, with the counts the lists show" do
      sign_in_as(admin)
      get "/poam_documents"

      expect(tab_keys("org-tabs")).to eq(%i[overview boundaries baselines ssp cdef sap sar evidence poam people settings])
      expect(current_tab("org-tabs")).to eq(:poam)
      nav = BoundaryNavCounts.for(nil, admin)
      expect(tab_counts("org-tabs")).to include(ssp: nav[:ssp], evidence: nav[:evidence],
                                                boundaries: AuthorizationBoundary.count, poam: 6)
    end

    it "offers a member no admin tabs and counts only the boundaries they reach" do
      sign_in_as(member)
      get "/"

      expect(tab_keys("org-tabs")).not_to include(:people, :settings)
      expect(current_tab("org-tabs")).to eq(:overview)
      expect(tab_counts("org-tabs")).to include(boundaries: 2, ssp: 2, poam: 4)
    end

    it "is absent with SPARC_NAV_SHELL off" do
      allow(SparcConfig).to receive(:nav_shell?).and_return(false)
      sign_in_as(admin)
      [ "/", "/ssp_documents", "/authorization_boundaries" ].each do |path|
        get path
        expect(page.at_css("[data-testid=shell-bar]")).to be_nil, path
      end
    end
  end

  describe "inside a boundary" do
    before { sign_in_as(member) }

    it "names the boundary and offers its own tabs on its page" do
      get "/authorization_boundaries/#{alpha.to_param}"

      expect(page.at_css("[data-testid=shell-boundary]").text).to eq("Alpha ATO")
      expect(current_tab("boundary-tabs")).to eq(:overview)
      expect(tab_counts("boundary-tabs")).to include(ssp: 1, poam: 2)
      poams = tabs("boundary-tabs").find { _1["data-tab"] == "poam" }["href"]
      expect(Rack::Utils.parse_query(URI(poams).query)).to eq("authorization_boundary_id" => alpha.id.to_s)
    end

    it "keeps the boundary's tabs on a list filtered to it" do
      get "/poam_documents", params: { authorization_boundary_id: alpha.id }

      expect(page.at_css("[data-testid=org-tabs]")).to be_nil
      expect(current_tab("boundary-tabs")).to eq(:poam)
      expect(tab_counts("boundary-tabs")).to eq(BoundaryNavCounts.for(alpha, member).slice(:ssp, :cdef, :sap, :sar, :evidence, :poam))
    end

    it "never names a boundary the viewer cannot reach" do
      get "/poam_documents", params: { authorization_boundary_id: hidden.id }

      expect(page.at_css("[data-testid=boundary-tabs]")).to be_nil
      expect(page.at_css("[data-testid=org-tabs]")).to be_present
      expect(response.body).not_to include("Hidden ATO")
    end
  end

  describe "the Overview" do
    it "keeps the inventory and every homepage card, with the classic page's counts" do
      sign_in_as(admin)
      allow(SparcConfig).to receive(:nav_shell?).and_return(false)
      get "/"
      classic = page.css("[data-home-count]").to_h { [ _1["data-home-count"], _1.text.squish.delete(",").to_i ] }
      classic_tiles = page.css("[data-home-tile]").map { _1["data-home-tile"] }

      allow(SparcConfig).to receive(:nav_shell?).and_return(true)
      get "/"
      boxes = page.css("[data-testid=org-box]").to_h do
        [ _1["data-home-count"], _1.at_css(".sparc-lane-box__count").text.delete(",").to_i ]
      end

      expect(page.css("[data-home-tile]").map { _1["data-home-tile"] }).to eq(classic_tiles)
      expect(boxes).to include(classic)
      expect(page.css("[data-testid=org-lane]").map { _1["data-layer"] }).to eq(%w[controls implementation assessment enterprise])
    end

    it "adds the Enterprise routing boxes for whoever their screens admit" do
      sign_in_as(admin)
      get "/"
      enterprise = page.css("[data-layer=enterprise] [data-testid=org-box]").map { _1["data-home-count"] }
      expect(enterprise).to eq(%w[organizations authorization_boundaries federation_peers authoritative_sources])

      sign_in_as(member)
      get "/"
      enterprise = page.css("[data-layer=enterprise] [data-testid=org-box]").map { _1["data-home-count"] }
      expect(enterprise).to eq(%w[authorization_boundaries])
    end

    it "offers New only where the create action would admit the viewer" do
      sign_in_as(member)
      get "/"
      catalogs = page.css("[data-testid=org-box]").find { _1["data-home-count"] == "control_catalogs" }

      expect(catalogs.at_css(".sparc-lane-box__new")).to be_nil
    end

    it "lists only reachable boundaries in the rail" do
      sign_in_as(member)
      get "/"
      names = page.css("[data-testid=org-recent-boundaries] a").map(&:text)

      expect(names).to contain_exactly("Alpha ATO", "Bravo ATO")
    end
  end

  describe "the Boundaries tab" do
    def rows = page.css("[data-testid=boundary-row]")

    def row(boundary) = page.at_css("[data-testid=boundary-row][data-boundary-id='#{boundary.id}']")

    it "lists only the boundaries the viewer may see, with their lists' counts" do
      sign_in_as(member)
      get "/authorization_boundaries"

      expect(rows.map { _1["data-boundary-id"].to_i }).to contain_exactly(alpha.id, bravo.id)
      expect(row(alpha).at_css("[data-testid=row-poams]").text.squish).to eq("2 POA&Ms")
      expect(response.body).not_to include("Hidden ATO")
    end

    it "filters by assignment and status, with counts" do
      sign_in_as(member)
      create(:user_role, user: admin, role: member_role, authorization_boundary: hidden)
      sign_in_as(admin)
      get "/authorization_boundaries"
      filter = page.at_css("[data-testid=boundaries-filter]")
      expect(filter.at_css("[data-testid=boundaries-filter-all] .sparc-counter").text).to eq("3")
      expect(filter.at_css("[data-testid=boundaries-filter-mine] .sparc-counter").text).to eq("1")

      get filter.at_css("[data-testid=boundaries-filter-mine]")["href"]
      expect(rows.map { _1["data-boundary-id"].to_i }).to eq([ hidden.id ])

      get "/authorization_boundaries", params: { status: "draft" }
      expect(rows.map { _1["data-boundary-id"].to_i }).to eq([ bravo.id ])
      expect(page.at_css("[data-testid=boundaries-filter-status][aria-current=true]")["data-status"]).to eq("draft")
    end

    it "draws each boundary's documentation activity" do
      ssp = SspDocument.find_by!(authorization_boundary: alpha)
      3.times { AuditEvent.create!(action: "ssp_document_created", subject_type: "SspDocument", subject_id: ssp.id) }
      sign_in_as(member)
      get "/authorization_boundaries"

      expect(row(alpha).at_css("[data-testid=boundary-sparkline]")["data-total"]).to eq("3")
      expect(row(bravo).at_css("[data-testid=boundary-sparkline]")["data-total"]).to eq("0")
    end

    it "keeps the classic list, with bulk delete, a click away for administrators" do
      sign_in_as(admin)
      get "/authorization_boundaries", params: { classic: 1 }

      expect(rows).to be_empty
      expect(response.body).to include("Authorization Boundaries")
    end
  end
end
