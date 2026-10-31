# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1301 — the boundary page under SPARC_NAV_SHELL is a home for the
# boundary: the page header with every header action, the latest activity,
# one row per document, the weekly activity (scan runs and validations
# included), readiness as the API reports it, and an About column with the
# facts, tags and what needs attention. The sections below stay, so no action
# the page had is lost. With the switch off the page is as before.
RSpec.describe "Boundary home (#1301)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:baseline) do
    controls = %w[ac-1 ac-2 au-2].map { { "id" => _1, "title" => _1.upcase } }
    create(:profile_document, name: "Moderate baseline",
           resolved_catalog_json: { "catalog" => { "groups" => [ { "id" => "all", "controls" => controls } ] } })
  end
  let(:boundary) do
    create(:authorization_boundary, name: "Home Sys", status: "active", description: "Payroll for HQ",
           profile_document: baseline)
  end

  def page = Nokogiri::HTML(response.body)

  def home = page.at_css("[data-testid=boundary-home]")

  def doc_row(key) = page.at_css("[data-testid=boundary-documents] [data-document='#{key}']")

  def attention(key) = page.at_css("[data-testid=boundary-attention] [data-attention='#{key}']")

  def shell(on) = allow(SparcConfig).to(receive_messages(any_auth_enabled?: true, nav_shell?: on))

  before { sign_in_as(admin) }

  context "with SPARC_NAV_SHELL on" do
    before { shell(true) }

    describe "the header" do
      it "is the page header: the name as h1, its status, Build ATO Package and the More menu" do
        get authorization_boundary_path(boundary)

        header = page.at_css("[data-testid=page-header]")
        expect(header.at_css("h1").text).to eq("Home Sys")
        expect(header.at_css("[data-testid=page-header-chip]").text).to eq("Active")
        expect(header.at_css("[data-boundary-action='build_ato_package']")["href"]).to eq(ato_wizard_authorization_boundary_path(boundary))
        expect(header.at_css("#boundary-more-menu")).to be_present
      end
    end

    describe "the documents" do
      it "lists one row per document in OSCAL's order, adding what is missing" do
        ssp = create(:ssp_document, name: "Home SSP", authorization_boundary: boundary)
        create_list(:poam_document, 2, authorization_boundary: boundary)
        get authorization_boundary_path(boundary)

        rows = page.css("[data-testid=boundary-documents] [data-document]").map { _1["data-document"] }
        expect(rows).to eq(%w[profile ssp cdef sap sar poam leveraged])
        expect(doc_row(:profile).text).to include("Moderate baseline")
        expect(doc_row(:ssp).at_css("a")["href"]).to eq(ssp_document_path(ssp))
        expect(doc_row(:sap).at_css("a")["href"]).to eq(attach_document_authorization_boundary_path(boundary, type: "sap"))
        expect(doc_row(:poam).at_css("a").text).to eq("2 POA&Ms")
        expect(doc_row(:poam).at_css("a")["href"]).to eq(BoundaryScopedList.path(:poam, boundary))
        expect(doc_row(:leveraged).text).to include("None")
      end

      it "counts CDEFs as the boundary's CDEF list does" do
        get authorization_boundary_path(boundary)
        expected = BoundaryScopedList.narrow(:cdef, CdefDocument.all, boundary.id).count
        expect(doc_row(:cdef).text.squish).to include(expected.zero? ? "Add…" : "#{expected} CDEF")
      end
    end

    describe "activity" do
      it "shows the latest change, and counts scan runs and validations week by week" do
        run = create(:scan_run, authorization_boundary: boundary)
        validation = create(:ksi_validation, authorization_boundary: boundary)
        create(:audit_event, action: "scan_run_ingested", subject_type: "ScanRun", subject_id: run.id, created_at: 2.hours.ago)
        create(:audit_event, action: "ksi_validation_created", subject_type: "KsiValidation", subject_id: validation.id,
               created_at: 1.hour.ago, user: admin)
        get authorization_boundary_path(boundary)

        expect(page.at_css("[data-testid=boundary-latest-activity]").text.squish).to include("ksi validation created")
        expect(page.at_css("[data-testid=boundary-activity-chart]")["data-total"]).to eq("2")
      end

      it "says so when nothing has happened" do
        get authorization_boundary_path(boundary)
        expect(page.at_css("[data-testid=boundary-latest-activity]").text).to include("No recorded activity")
      end
    end

    it "shows readiness as the API reports it" do
      get authorization_boundary_path(boundary)
      shown = page.at_css("[data-testid=boundary-readiness-bar] [data-readiness-complete]")["data-readiness-complete"].to_i
      expect(shown).to eq(BoundaryReadinessService.new(boundary).report[:summary][:complete])
      expect(page.at_css("[data-testid=boundary-readiness-bar] code").text)
        .to include(api_v1_authorization_boundary_readiness_path(boundary.id))
    end

    describe "the About column" do
      it "shows the facts and the tags" do
        boundary.update!(next_decision_date: Date.current - 3, authorization_status: "Authorized", authorizing_official: "Dana Official")
        create(:authorization_boundary_membership, authorization_boundary: boundary, role: "isso", user_name: "Sam Isso")
        get authorization_boundary_path(boundary)

        about = page.at_css(".sparc-boundary-home__about")
        expect(about.at_css("[data-boundary-fact='authorizing_official']").text).to eq("Dana Official")
        expect(about.at_css("[data-boundary-fact='isso']").text).to eq("Sam Isso")
        expect(about.at_css("[data-boundary-fact='next_decision'] [data-next-decision='overdue']")).to be_present
        expect(page.css("[data-testid=boundary-tags] [data-tag]").map { _1["data-tag"] }).to include("baseline", "oscal")
        expect(page.at_css("[data-tag=oscal]").text).to eq("OSCAL #{OscalSchema::DEFAULT_VERSION}")
      end

      it "counts overdue POA&M items: past their deadline and not closed" do
        poam = create(:poam_document, authorization_boundary: boundary)
        create(:poam_item, poam_document: poam, deadline: Date.current - 1, risk_status: "open")
        create(:poam_item, poam_document: poam, deadline: Date.current - 1, risk_status: nil)
        create(:poam_item, poam_document: poam, deadline: Date.current - 1, risk_status: "closed")
        create(:poam_item, poam_document: poam, deadline: Date.current + 1, risk_status: "open")
        create(:poam_item, poam_document: create(:poam_document), deadline: Date.current - 1, risk_status: "open")
        get authorization_boundary_path(boundary)

        expect(attention(:overdue_poam_items)["data-count"]).to eq("2")
        expect(attention(:overdue_poam_items).text.squish).to eq("2 overdue POA&M items")
      end

      it "counts baseline controls no evidence in the boundary is linked to" do
        evidence = create(:evidence, authorization_boundary: boundary)
        # Stored as an older import left it, not canonicalised.
        create(:evidence_control_link, evidence: evidence, control_id: "ac-1").update_column(:control_id, "AC-1")
        other = create(:evidence, authorization_boundary: create(:authorization_boundary))
        create(:evidence_control_link, evidence: other, control_id: "AU-2")
        get authorization_boundary_path(boundary)

        expect(attention(:controls_without_evidence)["data-count"]).to eq("2")
      end

      it "says there is nothing to measure without a baseline" do
        bare = create(:authorization_boundary)
        get authorization_boundary_path(bare)
        expect(attention(:controls_without_evidence).text).to include("No baseline")
      end

      it "shows the SSP's answered responses as the SSP list counts them" do
        # No baseline, so the SSP's own controls are what it must answer.
        bare = create(:authorization_boundary)
        ssp = create(:ssp_document, authorization_boundary: bare, profile_document: nil)
        %w[ac-1 ac-2].each { create(:ssp_control, ssp_document: ssp, control_id: _1) }
        get authorization_boundary_path(bare)

        total = SspResponseProgress.for(ssp).total
        expect(total.required).to be > total.done
        item = attention(:ssp_completion)
        expect([ item["data-done"].to_i, item["data-required"].to_i ]).to eq([ total.done, total.required ])
      end
    end

    describe "nothing is lost" do
      # The 28-action inventory: every link and form on the switch-off page is
      # on the new one. Hash-only links (in-page jumps) are not actions.
      def actions
        root = page.at_css(".sparc-main-content > .container") || page.at_css("body > .container")
        links = root.css("a[href]").map { _1["href"] }.reject { _1.start_with?("#") }
        forms = root.css("form[action]").map { |f| [ f["action"], f.at_css("input[name=_method]")&.[]("value") || f["method"] ].join(" ") }
        (links + forms).to_set
      end

      it "keeps every action the page had" do
        create(:ssp_document, authorization_boundary: boundary)
        create(:sap_document, authorization_boundary: boundary)
        create(:poam_document, authorization_boundary: boundary)
        create(:boundary, authorization_boundary: boundary)
        create(:authorization_boundary_membership, authorization_boundary: boundary, role: "isso", user_name: "Sam Isso")
        create(:evidence, authorization_boundary: boundary)
        create(:leveraged_authorization, leveraging_boundary: boundary)

        shell(false)
        get authorization_boundary_path(boundary)
        classic = actions
        expect(classic.size).to be >= 20

        shell(true)
        get authorization_boundary_path(boundary)
        expect(classic - actions).to be_empty
      end
    end
  end

  context "with SPARC_NAV_SHELL off" do
    before { shell(false) }

    it "draws the page as before" do
      get authorization_boundary_path(boundary)
      expect(home).to be_nil
      expect(page.at_css("header h2").text).to eq("Home Sys")
      expect(page.at_css("#boundary-artifacts")).to be_present
    end
  end
end
