# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1303 — administration under SPARC_NAV_SHELL: the Settings tab
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

  context "with SPARC_NAV_SHELL on" do
    before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true) }

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

  context "with SPARC_NAV_SHELL off" do
    before do
      allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: false)
      sign_in_as(admin)
    end

    it "has no settings page, menu or shared header" do
      get admin_settings_path
      expect(response).to have_http_status(:not_found)

      get admin_users_path
      expect(menu).to be_nil
      expect(page.at_css("h1").text).to eq("User Management")
      expect(page.at_css("[data-testid=status-tabs]")).to be_nil
    end

    it "still filters users by status as before" do
      create(:user, email: "gone@example.com", status: "deactivated")
      get admin_users_path(status: "active")
      expect(response.body).not_to include("gone@example.com")
    end
  end
end
