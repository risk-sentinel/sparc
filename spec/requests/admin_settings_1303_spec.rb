# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1303 — administration: the Settings tab
# opens a settings page listing every admin screen; each admin screen shows
# that menu beside it and the shared page header; the admin lists get the
# shared search and status tabs (service accounts are paginated). Who may
# open an admin screen does not change.
RSpec.describe "Admin settings (#1303)", type: :request do
  let(:admin) { create(:user, :admin) }

  def page = Nokogiri::HTML(response.body)

  def menu = page.at_css("[data-testid=admin-settings-menu]")

  def tab_count(slug) = page.at_css("[data-testid=status-tab][data-tab='#{slug}']")["data-count"].to_i

  def admin_screens = {
    "users" => "/admin/users", "roles" => "/admin/roles", "service_accounts" => "/admin/service_accounts",
    "idp_grants" => "/admin/idp_grants", "organizations" => "/admin/organizations",
    "authorization_boundaries" => "/admin/authorization_boundaries",
    "remediation_timelines" => "/admin/remediation_timelines", "audit_logs" => "/admin/audit_logs",
    "reconciliation" => "/admin/reconciliation", "data_migrations" => "/admin/data_migrations"
  }

  context "in the 1.18.0-rf navigation" do
    before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true) }

    describe "the settings page" do
      before { sign_in_as(admin) }

      it "is the Settings tab, and lists every admin screen" do
        get root_path
        expect(page.at_css("[data-testid=shell-tab][data-tab=settings]")["href"]).to eq(admin_settings_path)

        get admin_settings_path
        expect(response).to have_http_status(:ok)
        listed = page.css("[data-testid=admin-settings-item]").map { _1["href"] }
        expect(listed).to match_array(admin_screens.values)
        expect(page.at_css("[data-testid=shell-tab][aria-current=page]")["data-tab"]).to eq("settings")
      end

      # #1349 — the home page's group colours, one per section: the heading's
      # bar and every card's accent, from existing accent classes only.
      it "colours each section with one of the home page's group colours" do
        get admin_settings_path
        sections = page.css("[data-testid=admin-settings-section]")
        colours = sections.map { |sec| sec["class"][/sparc-accent--\w+/] }
        expect(sections.map { _1.at_css("h2").text.strip }).to eq(%w[Access Organization Records])
        expect(colours).to eq(%w[sparc-accent--blue sparc-accent--purple sparc-accent--carrot])
        sections.each do |sec|
          expect(sec.at_css("h2 .sparc-group-bar")).to be_present
          items = sec.css("[data-testid=admin-settings-item]")
          expect(items).not_to be_empty
          expect(items.map { _1["class"].split }).to all(include("sparc-section-card--accented"))
        end
      end

      it "opens every screen it lists" do
        admin_screens.each_value do |path|
          get path
          expect(response).to have_http_status(:ok), path
        end
      end
    end

    describe "each admin screen" do
      before { sign_in_as(admin) }

      it "shows the settings menu with itself current, and the shared page header" do
        admin_screens.each do |key, path|
          get path

          expect(menu).to be_present, path
          expect(menu.at_css("[aria-current=page]")["data-item"]).to eq(key), path
          expect(page.css("[data-testid=page-header] h1").size).to eq(1), path
        end
      end

      it "puts admin screens under Settings and Users under People" do
        get admin_audit_logs_path
        expect(page.at_css("[data-testid=shell-tab][aria-current=page]")["data-tab"]).to eq("settings")

        get admin_users_path
        expect(page.at_css("[data-testid=shell-tab][aria-current=page]")["data-tab"]).to eq("people")
      end
    end

    describe "the admin lists" do
      before { sign_in_as(admin) }

      # #1349 — the users list fits beside the menu: the Admin badge sits in the
      # Status column, and the last sign-in stacks its date over its time.
      it "shows a user's Admin badge with their status, in one fewer column" do
        admin.update!(last_sign_in_at: Time.zone.parse("2026-11-05 15:20"))
        get admin_users_path
        heads = page.css(".sparc-list-card thead th").map { _1.text.strip }
        expect(heads).to eq(["Email", "Name", "Status", "Roles", "Sign-ins", "Last active", ""])
        row = page.css(".sparc-list-card tbody tr").find { _1.text.include?(admin.email) }
        status = row.css("td")[2]
        expect(status.css(".badge").map { _1.text.strip }).to include("Active", "Admin")
        expect(row.css("td").size).to eq(heads.size)
        expect(row.at_css("td.sparc-cell-break").text.strip).to eq(admin.email)
        expect(row.css("td")[5].css(".sparc-stamp > span").map(&:text)).to eq(%w[2026-11-05 15:20])
      end

      it "stacks an audit event's date over its time, seconds kept" do
        create(:audit_event, created_at: Time.zone.parse("2026-11-05 15:20:42"))
        get admin_audit_logs_path
        stamps = page.css(".sparc-list-card tbody td .sparc-stamp").map { |st| st.css("> span").map(&:text) }
        expect(stamps).to include(%w[2026-11-05 15:20:42])
      end

      it "counts users by status, narrows by tab and keeps the search" do
        create(:user, email: "sam.active@example.com")
        create(:user, email: "sam.suspended@example.com", status: "suspended")
        create(:user, email: "other@example.com", status: "suspended")
        get admin_users_path(q: "sam")

        expect([ tab_count("all"), tab_count("active"), tab_count("suspended") ]).to eq([ 2, 1, 1 ])
        get page.at_css("[data-testid=status-tab][data-tab=suspended]")["href"]
        expect(response.body).to include("sam.suspended@example.com")
        expect(response.body).not_to include("sam.active@example.com", "other@example.com")
        expect(page.css("[data-testid=filter-token]").map { _1.text.squish }).to eq([ "search: sam" ])
      end

      it "counts organizations by status" do
        create(:organization, status: "active")
        create(:organization, status: "inactive")
        get admin_organizations_path

        expect([ tab_count("active"), tab_count("inactive") ]).to eq([ 1, 1 ])
      end

      it "paginates service accounts" do
        create_list(:user, 26, :service_account)
        get admin_service_accounts_path

        expect(page.at_css("output").text.squish).to start_with("1–25 of 26")
        get admin_service_accounts_path(page: 2)
        expect(page.css("tbody tr").size).to eq(1)
      end

      it "searches roles and boundaries" do
        create(:authorization_boundary, name: "Findable ATO", status: "active")
        create(:authorization_boundary, name: "Hidden ATO")
        get admin_authorization_boundaries_path(q: "Findable")
        # The table, not the page: the header's switcher lists every boundary.
        rows = page.css("tbody tr").map { _1.text.squish }.join(" ")
        expect(rows).to include("Findable ATO")
        expect(rows).not_to include("Hidden ATO")
        expect(tab_count("active")).to eq(1)

        create(:role, name: "findable_role", display_name: "Findable role")
        create(:role, name: "other_role", display_name: "Other role")
        get admin_roles_path(q: "findable")
        rows = page.css("tbody tr").map { _1.text.squish }
        expect(rows.size).to eq(1)
        expect(rows.first).to include("Findable role")
      end
    end

    describe "who may open it" do
      it "is refused to a signed-in member, who has no Settings tab" do
        member = create(:user)
        sign_in_as(member)

        get root_path
        expect(page.at_css("[data-testid=shell-tab][data-tab=settings]")).to be_nil

        get admin_settings_path
        expect(response).not_to have_http_status(:ok)
        expect(response.body).not_to include("admin-settings")
      end

      it "is refused to someone signed out" do
        get admin_settings_path
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
