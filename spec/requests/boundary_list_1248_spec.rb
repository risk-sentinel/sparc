# frozen_string_literal: true

require "rails_helper"

# #1248 — the Authorization Boundaries list answers the questions people bring
# to it: whose system, its status, and when its next decision is due.
#
#   * Columns: Name (description as tooltip), Organization (only when the
#     visible boundaries span more than one), Status, Next decision, Members,
#     Environments, Actions.
#   * Next decision sorts through AuthorizationBoundary.sorted_by, an
#     allow-list, with empty dates last; the API takes the same `sort`.
#   * Next-decision badge: warning within 90 days, red once past (owner).
#   * Row actions: View only. Bulk delete for administrators stays.
#   * GET /api/v1/authorization_boundaries lists AuthorizationBoundary.visible_to.
RSpec.describe "Authorization boundary list (#1248)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:org_a) { create(:organization, name: "Agency Alpha") }
  let(:org_b) { create(:organization, name: "Agency Bravo") }
  let(:page)  { Nokogiri::HTML(response.body) }

  def boundary(name, next_decision: nil, org: org_a, **attrs)
    create(:authorization_boundary, name: name, organization: org, **attrs).tap do |b|
      b.update!(next_decision_date: next_decision) if next_decision
    end
  end

  def row_names = page.css("tbody tr td:nth-child(#{admin_offset + 1}) a").map(&:text)
  def admin_offset = 1 # the bulk-select column an administrator sees

  describe "columns" do
    before { sign_in_as(admin) }

    it "puts the description in the name's tooltip, not a column of its own" do
      boundary("Tooltip Sys", description: "Payroll processing for HQ")

      get authorization_boundaries_path(view: "list")

      headers = page.css("thead th").map { |th| th.text.squish }
      expect(headers).to include("Name", "Status", "Members", "Environments", "Actions")
      expect(headers.join(" ")).to include("Next decision")
      expect(headers).not_to include("Description")
      cell = page.css("tbody td").find { |td| td.text.include?("Tooltip Sys") }
      expect(cell["title"]).to eq("Payroll processing for HQ")
    end

    it "shows Organization only when the visible boundaries span more than one" do
      boundary("Alpha One")
      boundary("Alpha Two")
      get authorization_boundaries_path(view: "list")
      expect(page.css("thead th").map { |th| th.text.squish }).not_to include("Organization")

      boundary("Bravo One", org: org_b)
      get authorization_boundaries_path(view: "list")
      expect(page.css("thead th").map { |th| th.text.squish }).to include("Organization")
      expect(page.text).to include("Agency Bravo")
    end

    it "offers View only on each row, and keeps bulk delete for an administrator" do
      b = boundary("Row Actions Sys")

      get authorization_boundaries_path(view: "list")

      expect(response.body).not_to include(edit_authorization_boundary_path(b))
      expect(page.at_css("form[action='#{authorization_boundary_path(b)}']")).to be_nil
      expect(page.at_css("form[action='#{bulk_destroy_authorization_boundaries_path}']")).to be_present

      get authorization_boundaries_path(view: "card")
      expect(response.body).not_to include(edit_authorization_boundary_path(b))
      expect(page.at_css("form[action='#{authorization_boundary_path(b)}']")).to be_nil
    end
  end

  describe "the next-decision badge" do
    before { sign_in_as(admin) }

    it "is red once past, a warning within 90 days, neutral beyond, a dash when unset" do
      boundary("Past Sys", next_decision: Date.current - 1)
      boundary("Soon Sys", next_decision: Date.current + 90)
      boundary("Later Sys", next_decision: Date.current + 91)
      boundary("Unset Sys")

      %w[list card].each do |view|
        get authorization_boundaries_path(view: view)
        states = page.css("[data-next-decision]").map { |el| el["data-next-decision"] }
        expect(states).to include("overdue", "due_soon", "scheduled", "none"), view
        expect(page.at_css("[data-next-decision='overdue']")["class"]).to include("sparc-status--danger")
        expect(page.at_css("[data-next-decision='due_soon']")["class"]).to include("sparc-status--warning")
        expect(page.at_css("[data-next-decision='scheduled']")["class"]).to include("sparc-status--neutral")
      end
    end

    it "reads a legacy value that is not a date without failing" do
      helper = ApplicationController.helpers
      expect(helper.next_decision_state("not-a-date")).to eq(:unreadable)
      expect(helper.next_decision_state(nil)).to eq(:none)
      expect(helper.next_decision_state("2000-01-01")).to eq(:overdue)
    end
  end

  describe "sorting by next decision" do
    before do
      boundary("B Sys", next_decision: "2031-06-01")
      boundary("A Sys", next_decision: "2030-01-15")
      boundary("C Sys")
      sign_in_as(admin)
    end

    it "sorts ascending and descending, with empty dates last either way" do
      get authorization_boundaries_path(view: "list", sort: "next_decision")
      expect(row_names).to eq([ "A Sys", "B Sys", "C Sys" ])
      expect(page.at_css("th[aria-sort='ascending']")).to be_present
      # The header now offers the other direction.
      expect(page.at_css("a[data-sort-column='next_decision']")["href"]).to include("sort=-next_decision")

      get authorization_boundaries_path(view: "list", sort: "-next_decision")
      expect(row_names).to eq([ "B Sys", "A Sys", "C Sys" ])
    end

    it "ignores a sort that is not on the allow-list" do
      get authorization_boundaries_path(view: "list", sort: "name; drop table users")

      expect(response).to have_http_status(:ok)
      expect(page.at_css("th[aria-sort='none']")).to be_present
    end

    it "never interpolates the key: sorted_by leaves an unknown key's order alone" do
      relation = AuthorizationBoundary.order(:name)
      expect(relation.sorted_by("updated_at desc; --").to_sql).to eq(relation.to_sql)
    end
  end

  describe "GET /api/v1/authorization_boundaries" do
    let(:user) { create(:user) }
    let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'list-1248').plaintext_token}" } }
    let!(:readable)  { boundary("Readable Sys") }
    let!(:role_only) { boundary("Role Only Sys") }
    let!(:unrelated) { boundary("Unrelated Sys") }

    def names = response.parsed_body["data"].map { |row| row["name"] }

    it "lists only the boundaries the caller may read (visible_to)" do
      grant_permission(user, AuthorizationBoundary::READ_PERMISSION, authorization_boundary: readable)
      # A role on the boundary that does NOT grant read: the old index
      # (current_user.authorization_boundaries) listed it, and show refused it.
      grant_permission(user, "ssp.read", authorization_boundary: role_only)

      get "/api/v1/authorization_boundaries", headers: headers

      expect(response).to have_http_status(:ok)
      expect(names).to eq([ "Readable Sys" ])
    end

    it "lists every boundary for an instance-wide read grant" do
      grant_permission(user, AuthorizationBoundary::READ_PERMISSION)

      get "/api/v1/authorization_boundaries", headers: headers

      expect(names).to include("Readable Sys", "Role Only Sys", "Unrelated Sys")
    end

    it "sorts by next decision with the list page's allow-list, and refuses anything else" do
      grant_permission(user, AuthorizationBoundary::READ_PERMISSION)
      readable.update!(next_decision_date: "2032-01-01")
      unrelated.update!(next_decision_date: "2030-01-01")

      get "/api/v1/authorization_boundaries", headers: headers, params: { sort: "next_decision" }
      expect(names).to eq([ "Unrelated Sys", "Readable Sys", "Role Only Sys" ])

      get "/api/v1/authorization_boundaries", headers: headers, params: { sort: "name" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to include("next_decision")
    end
  end
end
