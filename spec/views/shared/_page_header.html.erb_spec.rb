# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1298 — the shared page header: a breadcrumb whose last entry is the
# current page, a title with status chips, and one primary action with the
# others folding into "More actions" at phone width.
RSpec.describe "shared/_page_header.html.erb", type: :view do
  def doc = Nokogiri::HTML(rendered)

  it "renders the breadcrumb with the current page unlinked" do
    render partial: "shared/page_header",
           locals: { title: "Alpha ATO", crumbs: [ [ "Agency", "/" ], [ "Boundaries", "/authorization_boundaries" ], [ "Alpha ATO", nil ] ] }

    crumbs = doc.css("nav[aria-label=Breadcrumb] li")
    expect(crumbs.map { _1.text.squish }).to eq([ "Agency", "Boundaries", "Alpha ATO" ])
    expect(crumbs.last["aria-current"]).to eq("page")
    expect(crumbs.last.at_css("a")).to be_nil
    expect(crumbs.first.at_css("a")["href"]).to eq("/")
  end

  it "renders the title, chips and actions" do
    render partial: "shared/page_header",
           locals: { title: "Alpha ATO", chips: [ { label: "Active", intent: "info" } ],
                     primary: { label: "Edit", path: "/edit" },
                     secondary: [ { label: "Export", path: "/export" } ] }

    expect(doc.at_css("h1").text).to eq("Alpha ATO")
    expect(doc.at_css("[data-testid=page-header-chip]")["class"]).to include("sparc-status-chip--info")
    actions = doc.at_css("[data-testid=page-header-actions]")
    expect(actions.css("a.sparc-page-header__secondary").map(&:text)).to eq([ "Export" ])
    expect(actions.css(".sparc-page-header__overflow .dropdown-item").map(&:text)).to eq([ "Export" ])
    expect(actions.css("a.sparc-action--solid").map(&:text)).to eq([ "Edit" ])
  end

  it "renders no breadcrumb, chips or actions when none are given" do
    render partial: "shared/page_header", locals: { title: "Boundaries" }

    expect(doc.at_css("nav[aria-label=Breadcrumb]")).to be_nil
    expect(doc.at_css("[data-testid=page-header-chip]")).to be_nil
    expect(doc.at_css("[data-testid=page-header-actions]")).to be_nil
  end
end
