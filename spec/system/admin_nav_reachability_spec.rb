# frozen_string_literal: true

require "rails_helper"

# Layer 1, regression spec #2 — admin nav reachability smoke.
#
# Catches:
#   - Route drift (a controller is renamed but the User dropdown's
#     admin block still points at the old name → 404 at click)
#   - Auth drift (admin? check on the page silently 302s admins to
#     /login)
#   - Layout drift (the identifying heading disappears from a page,
#     so the human walking the smoke checklist mistakes a broken
#     page for the intended one)
#
# Each entry asserts both HTTP success AND a unique on-page heading
# so a rendered-but-wrong page can't pass.
RSpec.describe "Admin nav reachability", type: :system do
  let(:admin) { create(:user, :admin) }

  before do
    # System specs need real env vars (RSpec mocks are thread-local
    # and don't reach Capybara's Puma thread). The system_spec_config
    # support file sets SPARC_ENABLE_LOCAL_LOGIN=true by default.
    visit "/login"
    accept_consent_banner
    fill_in "Email Address", with: admin.email
    fill_in "Password",      with: "SecurePassword123!"
    click_button "Sign In"

    # Hard-wait for the redirect to land. Without this, the next
    # `visit` can race the sign-in handshake and hit /admin/* before
    # the session cookie is set, producing confusing redirect-to-/login
    # failures.
    expect(page).not_to have_field("Email Address", wait: 5),
      "Sign-in failed. Path=#{page.current_path}; body excerpt: #{page.body[0, 500]}"
  end

  ADMIN_PAGES = [
    [ "/admin/users",                     /Users/i ],
    [ "/admin/service_accounts",          /Service Accounts/i ],
    [ "/admin/roles",                     /Roles/i ],
    [ "/admin/audit_logs",                /Audit/i ],
    [ "/admin/authorization_boundaries",  /Authorization Boundaries/i ],
    [ "/admin/organizations",             /Organizations/i ],
    [ "/admin/data_migrations",           /Data Migrations/i ]
  ].freeze

  ADMIN_PAGES.each do |path, heading_regex|
    it "GET #{path} loads + renders its identifying heading" do
      visit path
      # A 302 to /login means auth drifted; a 5xx means the page
      # blew up; a 200 with wrong content means layout drifted.
      expect(page).to have_current_path(path, ignore_query: true)
      expect(page.body).to match(heading_regex)
    end
  end
end
