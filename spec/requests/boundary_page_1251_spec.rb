# frozen_string_literal: true

require "rails_helper"

# #1251 — the boundary page says what the boundary IS before what it lacks:
#
#   * a header with name, UUID, status, authorization status, next decision and
#     authorizing official; the Details card is merged into it;
#   * Build ATO Package stays primary; everything else is in a "More" menu, and
#     Edit / Delete appear only to someone permitted, Delete explaining a
#     refusal before the click;
#   * collapsible sections, in a fixed order, each with a count; Completeness
#     open (and pinned open) while Draft, collapsed otherwise; Artifact Summary
#     open; the rest collapsed;
#   * Completeness rows link to where the work is done, only for someone who
#     may do it there; the guide stays a secondary link.
RSpec.describe "Boundary page (#1251)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin)    { create(:user, :admin) }
  let(:reader)   { create(:user).tap { |u| grant_permission(u, AuthorizationBoundary::READ_PERMISSION, authorization_boundary: boundary) } }
  let(:boundary) { create(:authorization_boundary, name: "Page Sys", status: "active", description: "Payroll for HQ") }
  let(:page)     { Nokogiri::HTML(response.body) }

  def section_ids = page.css("section.sparc-collapsible").map { |s| s["id"] }
  def body_of(id) = page.at_css("##{id}-body")
  def more_actions = page.css("[aria-labelledby='boundary-more-menu'] [data-boundary-action]").map { |el| el["data-boundary-action"] }

  describe "the header" do
    before do
      boundary.update!(next_decision_date: Date.current - 3, authorization_status: "Authorized (conditional)",
                       authorizing_official: "Dana Official")
      sign_in_as(admin)
      get authorization_boundary_path(boundary)
    end

    it "states the status and the key ATO facts, with the description under the name" do
      header = page.at_css("header")
      expect(header.at_css("h2").text).to eq("Page Sys")
      expect(header.at_css("[data-boundary-status]")["class"]).to include("sparc-status--info")
      expect(header.text).to include("Payroll for HQ")
      expect(header.at_css("[data-boundary-fact='authorization_status']").text).to include("Authorized (conditional)")
      expect(header.at_css("[data-boundary-fact='authorizing_official']").text).to include("Dana Official")
      expect(header.at_css("[data-boundary-fact='next_decision'] [data-next-decision='overdue']")).to be_present
    end

    it "keeps Build ATO Package primary and puts the rest in More" do
      expect(page.at_css("header [data-boundary-action='build_ato_package']")).to be_present
      expect(more_actions).to include("amendments", "cdef_coverage", "edit", "delete", "all_boundaries")
      expect(page.at_css("[data-boundary-action='amendments']").text).to eq("Amendments")
    end
  end

  describe "who is offered what" do
    it "offers a reader neither Build ATO Package, Edit nor Delete" do
      sign_in_as(reader)
      get authorization_boundary_path(boundary)

      expect(page.at_css("[data-boundary-action='build_ato_package']")).to be_nil
      expect(more_actions).not_to include("edit", "delete", "delete_refused")
      expect(more_actions).to include("all_boundaries")
    end

    it "offers a boundary writer Edit, and Delete only to an administrator" do
      grant_permission(reader, AuthorizationBoundary::WRITE_PERMISSION, authorization_boundary: boundary)
      sign_in_as(reader)
      get authorization_boundary_path(boundary)

      expect(more_actions).to include("edit")
      expect(more_actions).not_to include("delete", "delete_refused")
      expect(page.at_css("[data-boundary-action='build_ato_package']")).to be_present
    end

    it "explains a refused delete before the click, with the guard's own list" do
      create(:ssp_document, authorization_boundary: boundary)
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      refused = page.at_css("[data-boundary-action='delete_refused']")
      expect(refused.text).to include("Cannot delete while linked to 1 SSP(s)")
      expect(page.at_css("form[action='#{authorization_boundary_path(boundary)}'] input[value='delete']")).to be_nil
      expect(boundary.deletion_blockers).to eq([ "1 SSP(s)" ])
    end

    it "offers Delete, through the confirm modal, when nothing blocks it" do
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      form = page.at_css("form[action='#{authorization_boundary_path(boundary)}']")
      expect(form["data-turbo-confirm"]).to include("Delete 'Page Sys'?")
      expect(form.at_css("[data-boundary-action='delete']")).to be_present
    end
  end

  describe "the sections" do
    it "come in the owner's order, each with a count" do
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      expect(section_ids).to eq(%w[boundary-completeness boundary-artifacts boundary-environments
                                   boundary-personnel boundary-evidence boundary-back-matter
                                   boundary-leveraged boundary-metadata-sync])
      (section_ids - %w[boundary-completeness]).each do |id|
        expect(page.at_css("##{id} [data-section-count]")).to be_present, "#{id} has no count"
      end
      expect(page.at_css("#boundary-completeness [data-readiness-summary]").text).to match(/\d+ of 11 complete/)
      titles = page.css(".sparc-collapsible__title").map { |t| t.text.strip }
      expect(titles).to include("Evidence")
      expect(titles).not_to include("Artifacts")
    end

    it "open Completeness (pinned) on a Draft boundary, and collapse it otherwise" do
      sign_in_as(admin)
      draft = create(:authorization_boundary, status: "draft")

      get authorization_boundary_path(draft)
      expect(body_of("boundary-completeness")["class"]).to include("show")
      expect(body_of("boundary-completeness")["data-collapse-memory-pinned"]).to eq("open")

      get authorization_boundary_path(boundary)
      expect(body_of("boundary-completeness")["class"]).not_to include("show")
      expect(body_of("boundary-completeness")["data-collapse-memory-pinned"]).to be_nil
    end

    it "open Artifact Summary and collapse the rest by default" do
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      expect(body_of("boundary-artifacts")["class"]).to include("show")
      %w[boundary-environments boundary-personnel boundary-evidence boundary-back-matter
         boundary-leveraged boundary-metadata-sync].each do |id|
        expect(body_of(id)["class"]).not_to include("show"), "#{id} should start collapsed"
        toggle = page.at_css("[aria-controls='#{id}-body']")
        expect(toggle["aria-expanded"]).to eq("false")
      end
      expect(page.at_css("[data-controller='collapse-memory'][data-collapse-memory-key-value='boundary-page']")).to be_present
    end

    it "uses no inline handlers on the page's toggles" do
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      expect(response.body).not_to match(/\son[a-z]+="/i)
    end
  end

  describe "Completeness rows" do
    def row_link(key) = page.at_css("[data-readiness-row='#{key}'] a[data-readiness-action]")

    it "link each row to where its work is done, for an administrator" do
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      expect(row_link(:personnel)["href"]).to eq(new_authorization_boundary_membership_path(boundary))
      expect(row_link(:profile)["href"]).to eq(edit_authorization_boundary_path(boundary))
      expect(row_link(:ssp)["href"]).to eq(attach_document_authorization_boundary_path(boundary, type: "ssp"))
      expect(row_link(:leveraged)["href"]).to eq(new_authorization_boundary_leveraged_authorization_path(boundary))
      expect(row_link(:evidence)["href"]).to eq(new_evidence_path(authorization_boundary_id: boundary.id))
      expect(row_link(:scans)["href"]).to eq(triage_authorization_boundary_path(boundary))
      expect(row_link(:environments)["href"]).to eq(new_authorization_boundary_boundary_path(boundary))
      expect(row_link(:cdefs)["href"]).to eq(new_cdef_coverage_path(authorization_boundary_id: boundary.id))
      expect(row_link(:back_matter)["href"]).to eq(authorization_boundary_path(boundary, anchor: "boundary-back-matter"))
      expect(row_link(:back_matter)["data-action"]).to eq("collapse-memory#reveal")
    end

    it "lead to the prerequisite, labelled as such, when the SSP is missing" do
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      %i[classification components].each do |key|
        link = row_link(key)
        expect(link.text).to eq("Add SSP first")
        expect(link["href"]).to eq(attach_document_authorization_boundary_path(boundary, type: "ssp"))
      end
    end

    it "lead into the SSP once there is one" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      sign_in_as(admin)
      get authorization_boundary_path(boundary)

      expect(row_link(:ssp)["href"]).to eq(ssp_document_path(ssp))
      expect(row_link(:classification)["href"]).to eq(enrich_ssp_document_path(ssp, anchor: "info-types-container"))
      expect(row_link(:components)["href"]).to eq(enrich_ssp_document_path(ssp, anchor: "components-container"))
    end

    # Leveraged authorizations are guarded by boundary MEMBERSHIP, not a key
    # (LeveragedAuthorizationsController, #919 memo), and a role on the
    # boundary is membership, so that one row stays a link for this reader.
    it "offer a reader only the row their membership reaches, and keep every guide link" do
      sign_in_as(reader)
      get authorization_boundary_path(boundary)

      expect(page.css("a[data-readiness-action]").map { |a| a["data-readiness-action"] }).to eq([ "leveraged" ])
      expect(page.css("[data-readiness-row] a[href*='wiki/Adopting-OSCAL#']").size).to eq(11)
    end

    it "offer exactly the rows the reader's grants reach" do
      grant_permission(reader, "evidence.write", authorization_boundary: boundary)
      sign_in_as(reader)
      get authorization_boundary_path(boundary)

      expect(page.css("a[data-readiness-action]").map { |a| a["data-readiness-action"] })
        .to contain_exactly("evidence", "scans", "leveraged")
    end
  end
end
