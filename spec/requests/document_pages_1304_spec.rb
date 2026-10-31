# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1304 — the document pages under SPARC_NAV_SHELL share one header
# (shared/_document_header over shared/_page_header): a breadcrumb back to
# the boundary and list, the name as the one h1, lifecycle and approval
# chips, the name renamed in place as before, the export menu and Publish
# beside the page's own actions, and a sticky row of links to the page's
# sections, each of which exists on the page. With the switch off the pages
# are as before.
RSpec.describe "Document pages (#1304)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:boundary) { create(:authorization_boundary, name: "Doc ATO") }

  def page = Nokogiri::HTML(response.body)

  def header = page.at_css("[data-testid=page-header]")

  def crumbs = header.css(".sparc-page-header__crumbs li").map { [ _1.text.squish, _1.at_css("a")&.[]("href") ] }

  def section_targets = page.css("[data-testid=section-links] a").map { _1["href"].delete_prefix("#") }

  def open(record)
    get polymorphic_path(record)
    follow_redirect! while response.redirect?
    expect(response).to have_http_status(:ok)
  end

  def documents = {
    ssp: create(:ssp_document, authorization_boundary: boundary, status: "completed"),
    sap: create(:sap_document, authorization_boundary: boundary, status: "completed"),
    sar: create(:sar_document, authorization_boundary: boundary, status: "completed"),
    poam: create(:poam_document, authorization_boundary: boundary, status: "completed"),
    cdef: create(:cdef_document, status: "completed"),
    profile: create(:profile_document, status: "completed"),
    catalog: create(:control_catalog, status: "completed"),
    evidence: create(:evidence, authorization_boundary: boundary)
  }

  before { sign_in_as(admin) }

  context "with SPARC_NAV_SHELL on" do
    before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true) }

    it "gives every document page the header: one h1, a breadcrumb ending in the document, chips" do
      documents.each do |type, record|
        open(record)
        name = record.try(:name) || record.title
        expect(page.css("h1").map { _1.text.squish }).to eq([ header.at_css("h1").text.squish ]), type.to_s
        expect(crumbs.last).to eq([ header.at_css("h1").text.squish, nil ]), type.to_s
        expect(header.at_css("h1").text.squish).to include(name.squish.first(10)), type.to_s
        expect(header.css("[data-testid=page-header-chip]")).not_to be_empty, type.to_s
      end
    end

    it "leads back to the boundary and to the list within it" do
      ssp = documents[:ssp]
      open(ssp)
      expect(crumbs.first(2)).to eq([ [ "Doc ATO", authorization_boundary_path(boundary) ],
                                      [ "SSPs", BoundaryScopedList.path(:ssp, boundary) ] ])
    end

    it "names the boundary once, in the breadcrumb, and still warns when there is none" do
      ssp = documents[:ssp]
      open(ssp)
      # The page itself, not the top bar's boundary switcher.
      links = page.css("body > .container a[href='#{authorization_boundary_path(boundary)}']")
      expect(links.map { _1.ancestors("[data-testid=page-header]").any? }).to eq([ true ])

      # An older row from before a boundary was required.
      orphan = create(:ssp_document, status: "completed").tap { _1.update_column(:authorization_boundary_id, nil) }
      open(orphan)
      expect(page.text).to include("No boundary linked.")
    end

    it "links only to sections that are on the page" do
      documents.each do |type, record|
        open(record)
        section_targets.each { |id| expect(page.at_css("##{id}")).to be_present, "#{type}: ##{id}" }
      end
    end

    it "links to the heat map when the page draws one" do
      ssp = documents[:ssp]
      create(:ssp_control, ssp_document: ssp, control_id: "ac-1")
      open(ssp)
      expect(section_targets).to include("heatmapSection")
      expect(page.at_css("#heatmapSection")).to be_present
    end

    it "keeps the name renamed in place on the OSCAL documents" do
      documents.slice(:ssp, :sap, :sar, :poam, :cdef, :profile).each do |type, record|
        open(record)
        view = page.at_css("#doc-meta-view[data-doc-meta-target=view]")
        expect(view.at_css("h1")).to be_present, type.to_s
        expect(view.at_css("button[data-action='doc-meta#toggle']").text).to eq("Rename"), type.to_s
        form = page.at_css("#doc-meta-edit[data-doc-meta-target=edit] [data-testid=document-name-form]")
        expect(form["action"]).to eq(polymorphic_path(record, action: :update_metadata)), type.to_s
        expect(page.at_css("[data-controller~='doc-meta'] #doc-meta-view")).to be_present, type.to_s
      end
    end

    it "offers the export menu and, on a draft, Publish" do
      documents.slice(:ssp, :sap, :sar, :poam, :cdef).each do |type, record|
        record.update_columns(lifecycle_status: "in_progress")
        open(record)
        actions = header.at_css("[data-testid=page-header-actions]")
        expect(actions.text).to include("Export OSCAL", "Publish"), type.to_s
      end
    end

    it "submits a form for an action that changes something, asking first" do
      cdef = documents[:cdef]
      open(cdef)
      form = header.css("form").find { _1["action"] == copy_cdef_document_path(cdef) }
      expect(form["data-turbo-confirm"]).to eq("Duplicate this component definition?")
      expect(form.at_css("button").text).to eq("Copy")
    end

    it "keeps the review panel on a catalog" do
      catalog = documents[:catalog]
      open(catalog)
      expect(header.text).to include("Families").or include("families")
      expect(page.at_css("[data-testid=page-header] h1").text).to eq(catalog.name)
    end

    it "leads a leveraged POA&M back to the leveraged list, not to a boundary" do
      leveraged = create(:authorization_boundary, name: "Provider ATO")
      LeveragedAuthorization.create!(name: "LA", uuid: SecureRandom.uuid, leveraging_boundary: boundary,
                                     leveraged_boundary: leveraged, date_authorized: Date.new(2026, 1, 15))
      poam = create(:poam_document, name: "Provider POAM", authorization_boundary: leveraged)
      get leveraged_poam_document_path(poam)

      expect(crumbs).to eq([ [ "Leveraged POA&Ms", leveraged_poam_documents_path ], [ "Provider POAM", nil ] ])
      expect(header.text).to include("Inherited from Provider ATO")
    end
  end

  context "with SPARC_NAV_SHELL off" do
    before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: false) }

    it "draws every document page as before" do
      documents.each do |type, record|
        open(record)
        expect(header).to be_nil, type.to_s
        expect(page.at_css("[data-testid=section-links]")).to be_nil, type.to_s
        expect(page.at_css("h2")).to be_present, type.to_s
      end
    end
  end
end
