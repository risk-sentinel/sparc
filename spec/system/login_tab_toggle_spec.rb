# frozen_string_literal: true

require "rails_helper"

# Layer 1, regression spec #1 — would have caught the v1.7.0 Okta-tab
# CSP regression at PR time.
#
# Backstory: v1.7.0 (#514) enforced the page-level CSP without
# 'unsafe-inline' in script-src. The login page's tab buttons used
# inline `onclick="switchTab('tab-oidc')"` attributes — inline event
# handlers are blocked by enforced CSP and the page-level nonce only
# exempts <script nonce="..."> blocks, not inline-attribute handlers.
# Result: clicking the OIDC tab silently did nothing; users were
# stuck on the Local Login form for ~3 minor versions until a real
# user complained.
#
# A real browser would have surfaced this immediately — Chrome
# enforces CSP and blocks the inline handler. That's what this spec
# does: real Chrome, real CSP headers from
# config/initializers/content_security_policy.rb, real click.
RSpec.describe "Login page tab toggle", type: :system do
  before do
    # System specs run Puma in a separate thread; RSpec mocks are
    # thread-local. Use env vars (process-wide) so the controller
    # thread sees the flipped config.
    ENV["SPARC_ENABLE_OIDC"]           = "true"
    ENV["SPARC_OIDC_PROVIDER_TITLE"]   = "Okta"
    ENV["SPARC_OIDC_ISSUER_URL"]       = "https://dummy.example/oidc"
    ENV["SPARC_OIDC_CLIENT_ID"]        = "dummy"
  end

  it "renders both tabs and the Local panel is visible on first load" do
    visit "/login"
    expect(page).to have_button("Local Login")
    expect(page).to have_button("Okta")
    expect(page).to have_css('#tab-local.active')
    expect(page).not_to have_css('#tab-oidc.active')
  end

  it "switching to the Okta tab swaps panel visibility (the CSP regression case)" do
    visit "/login"
    click_button "Okta"
    # If inline onclick handlers were blocked (the v1.7.0 → v1.8.0
    # regression), this expectation fails because switchTab never
    # fires and the panel-active class never moves to the OIDC panel.
    expect(page).to have_css('#tab-oidc.active', wait: 2)
    expect(page).not_to have_css('#tab-local.active')
    expect(page).to have_button("Sign in with Okta")
  end

  it "switching back to Local restores the Local panel" do
    visit "/login"
    click_button "Okta"
    expect(page).to have_css('#tab-oidc.active', wait: 2)

    click_button "Local Login"
    expect(page).to have_css('#tab-local.active', wait: 2)
    expect(page).not_to have_css('#tab-oidc.active')
  end
end
