# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1299 — the collection screens under SPARC_NAV_SHELL: status tabs
# with counts, list rows, a third Table view, filter tokens and the filter
# form in the left column. With the switch off the screens draw what they
# drew before.
RSpec.describe "Collection screens (#1299)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:boundary) { create(:authorization_boundary, name: "Alpha ATO") }

  def page = Nokogiri::HTML(response.body)

  def tabs = page.css("[data-testid=status-tabs] [data-testid=status-tab]")

  def tab(slug) = page.at_css("[data-testid=status-tab][data-tab='#{slug}']")

  def count_of(slug) = tab(slug)["data-count"].to_i

  def listed?(doc) = response.body.include?(%(href="#{polymorphic_path(doc)}"))

  def tab_href(slug) = tab(slug)["href"]

  before { sign_in_as(admin) }

  context "with SPARC_NAV_SHELL on" do
    before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true) }

    describe "status tabs on the SSP list" do
      let!(:started)   { create(:ssp_document, name: "Started plan", authorization_boundary: boundary, lifecycle_status: "started") }
      let!(:drafts)    { create_list(:ssp_document, 2, authorization_boundary: boundary, lifecycle_status: "in_progress") }
      let!(:published) { create(:ssp_document, name: "Published plan", authorization_boundary: boundary, lifecycle_status: "published") }

      it "counts each state, and every count equals the rows behind its tab" do
        get ssp_documents_path(view: "list")

        expect(tabs.map(&:text).map(&:squish)).to eq([ "All 4", "Started 1", "Draft 2", "Published 1" ])
        expect(tab("all")["aria-current"]).to eq("true")

        %w[started draft published].each do |slug|
          get tab_href(slug)
          expect(page.css("[data-testid=collection-row]").size).to eq(count_of(slug)), slug
          expect(tab(slug)["aria-current"]).to eq("true")
        end
      end

      it "narrows to the chosen state and keeps the other params" do
        get ssp_documents_path(view: "list", per_page: 50, lifecycle_status: "published")

        expect(listed?(published)).to be(true)
        expect([ started, *drafts ].map { listed?(_1) }).to all(be(false))
        expect(tab_href("draft")).to include("per_page=50", "view=list", "lifecycle_status=in_progress")
        expect(tab_href("all")).not_to include("lifecycle_status")
      end

      it "counts over the list as searched, not over everything" do
        get ssp_documents_path(q: "Published plan")

        expect(count_of("all")).to eq(1)
        expect([ count_of("published"), count_of("draft") ]).to eq([ 1, 0 ])
      end

      it "shows nothing for a state that does not exist, rather than everything" do
        get ssp_documents_path(lifecycle_status: "bogus", view: "list")

        expect(page.css("[data-testid=collection-row]")).to be_empty
        expect(tabs.none? { _1["aria-current"] == "true" }).to be(true)
      end

      it "does not repeat the selected tab as a filter token" do
        get ssp_documents_path(lifecycle_status: "published", q: "plan")

        tokens = page.css("[data-testid=filter-token]").map(&:text).map(&:squish)
        expect(tokens).to eq([ "search: plan" ])
      end
    end

    describe "the three views" do
      let!(:doc) { create(:ssp_document, name: "Row plan", authorization_boundary: boundary) }

      it "draws rows for List, a table for Table and cards for Cards" do
        get ssp_documents_path(view: "list")
        expect(page.css("[data-testid=collection-row]").size).to eq(1)
        expect(page.css("table, .sparc-item-card")).to be_empty

        get ssp_documents_path(view: "table")
        expect(page.css("table tbody tr").size).to eq(1)
        expect(page.css("[data-testid=collection-row], .sparc-item-card")).to be_empty

        get ssp_documents_path(view: "card")
        expect(page.css(".sparc-item-card").size).to eq(1)
        expect(page.css("table, [data-testid=collection-row]")).to be_empty
      end

      it "offers Cards, List and Table, and remembers Table" do
        get ssp_documents_path(view: "table")

        options = page.css(".sparc-view-toggle [role=radio]")
        expect(options.map(&:text).map(&:squish)).to eq([ "▦Cards", "☰List", "▤Table" ])
        expect(options.find { _1["aria-checked"] == "true" }.text).to include("Table")
        expect(cookies["sparc_view_ssp_documents"]).to eq("table")
      end

      it "gives a row the card's actions" do
        get ssp_documents_path(view: "card")
        card_links = page.css(".sparc-item-card a").map { _1["href"] }.uniq.sort

        get ssp_documents_path(view: "list")
        row_links = page.css("[data-testid=collection-row] a").map { _1["href"] }.uniq.sort

        expect(row_links).to eq(card_links)
      end
    end

    describe "the filter form" do
      let!(:profile) { create(:profile_document, lifecycle_status: "published") }

      it "sits in the left column on a list with filters" do
        create(:profile_document, lifecycle_status: "in_progress", baseline_level: "LOW")
        create(:profile_document, lifecycle_status: "in_progress", baseline_level: "HIGH")
        get profile_documents_path

        side = page.at_css(".sparc-filtered-collection__side")
        expect(side.at_css("[data-testid=collection-filter-form]")).to be_present
        expect(page.css(".sparc-filtered-collection__main [data-testid=collection-filter-form]")).to be_empty
        # The status tab is the lifecycle filter; it is not offered twice.
        expect(side.at_css("select[name=lifecycle_status]")).to be_nil
      end

      it "shows each applied filter as a removable token" do
        get profile_documents_path(baseline_level: "LOW")

        token = page.at_css("[data-testid=filter-token]")
        expect(token.text.squish).to start_with("Baseline")
        expect(token.at_css("a")["href"]).not_to include("baseline_level")
      end
    end

    describe "the page header (#1298)" do
      it "heads every list with the shared page header, and nothing else" do
        %w[/ssp_documents /sap_documents /sar_documents /poam_documents /cdef_documents /profile_documents
           /control_catalogs /control_mappings /converters /evidences /federation_peers /review_queue
           /promotion_queue /authoritative_sources /leveraged_poam_documents].each do |path|
          get path
          expect(response).to have_http_status(:ok), path
          expect(page.css("[data-testid=page-header] h1").size).to eq(1), path
          expect(page.css(".card > .d-flex.justify-content-between > h2, .card-body > .d-flex.justify-content-between h2")).to be_empty, path
        end
      end

      it "puts a list's first create action first and folds the rest into More actions" do
        get ssp_documents_path
        actions = page.at_css("[data-testid=page-header-actions]")
        expect(actions.css("a.sparc-action--solid").map(&:text)).to eq([ "Create New SSP" ])
        expect(actions.css(".sparc-page-header__overflow .dropdown-item").map(&:text)).to eq([ "Upload File" ])
      end
    end

    describe "status tabs on the other lists" do
      it "adds Approved to the catalog tabs" do
        create(:control_catalog, lifecycle_status: "published", approval_status: "approved")
        create(:control_catalog, lifecycle_status: "published", approval_status: "draft")
        get control_catalogs_path(view: "list")

        expect(count_of("published")).to eq(2)
        expect(count_of("approved")).to eq(1)

        get tab_href("approved")
        expect(page.css("[data-testid=collection-row]").size).to eq(1)
      end

      it "counts evidence by status" do
        create(:evidence, authorization_boundary: boundary, status: "attested")
        create(:evidence, authorization_boundary: boundary, status: "draft")
        get evidences_path

        expect(count_of("attested")).to eq(1)
        expect(count_of("draft")).to eq(1)
      end

      it "counts control mappings and converters by status" do
        create(:control_mapping, status: "complete")
        create(:converter, status: "deprecated")

        get control_mappings_path
        expect(count_of("complete")).to eq(1)

        get converters_path
        expect(count_of("deprecated")).to eq(1)
      end

      it "draws no tabs on a screen with no status" do
        get review_queue_index_path
        expect(page.at_css("[data-testid=status-tabs]")).to be_nil
      end
    end
  end

  # The API filters by the same params, through the same definition, so a
  # tab's link and an API call with its params return the same documents.
  describe "the API (parity)" do
    let(:auth_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: "Test").plaintext_token}" } }

    it "narrows SSPs by lifecycle_status, and an unknown value to nothing" do
      published = create(:ssp_document, authorization_boundary: boundary, lifecycle_status: "published")
      create(:ssp_document, authorization_boundary: boundary, lifecycle_status: "in_progress")

      get api_v1_ssp_documents_path, params: { lifecycle_status: "published" }, headers: auth_headers
      expect(response.parsed_body["data"].map { _1["id"] }).to eq([ published.id ])

      get api_v1_ssp_documents_path, params: { lifecycle_status: "bogus" }, headers: auth_headers
      expect(response.parsed_body["data"]).to be_empty
    end

    it "narrows catalogs by approval_status" do
      approved = create(:control_catalog, approval_status: "approved")
      create(:control_catalog, approval_status: "draft")

      get api_v1_control_catalogs_path, params: { approval_status: "approved" }, headers: auth_headers
      expect(response.parsed_body["data"].map { _1["id"] }).to eq([ approved.id ])
    end
  end

  context "with SPARC_NAV_SHELL off" do
    before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: false) }

    let!(:doc) { create(:ssp_document, name: "Classic plan", authorization_boundary: boundary, lifecycle_status: "published") }

    it "draws no tabs and no rows; List and a stored Table both draw the table" do
      %w[list table].each do |mode|
        get ssp_documents_path(view: mode)

        expect(page.at_css("[data-testid=status-tabs]")).to be_nil
        expect(page.css("table tbody tr").size).to eq(1), mode
        expect(page.css("[data-testid=collection-row]")).to be_empty
        options = page.css(".sparc-view-toggle [role=radio]")
        expect(options.map(&:text).map(&:squish)).to eq([ "▦Cards", "☰List" ])
        expect(options.find { _1["aria-checked"] == "true" }.text).to include("List"), mode
      end
    end

    it "still narrows by a lifecycle link, and says so with a chip" do
      create(:ssp_document, name: "Draft plan", authorization_boundary: boundary, lifecycle_status: "in_progress")
      get ssp_documents_path(lifecycle_status: "published", view: "list")

      expect(response.body).to include("Classic plan")
      expect(response.body).not_to include("Draft plan")
      expect(page.at_css(".sparc-chip").text.squish).to start_with("Lifecycle: published")
    end
  end
end
