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
#
# #1082 — OIDC IS NO LONGER A TAB. A panel whose entire content is one button
# is not a tab, and OIDC was the only SSO method rendered as one, which made
# reaching Okta a two-click journey while FIDO2, PIV, GitHub and GitLab all sat
# one click away. The CSP mechanism this spec guards is unchanged and still
# needs a real-browser test, so the toggle is now exercised across the two
# FORM-based methods that legitimately need tabs: local login and LDAP.
RSpec.describe "Login page tab toggle", type: :system do
  # System specs run Puma in a separate thread; RSpec mocks are
  # thread-local. Use env vars (process-wide) so the controller
  # thread sees the flipped config.
  #
  # Restored afterwards — process-wide means these leak into every later spec
  # in the same run, and an auth toggle left on is not a harmless leak.
  # A `let`, not a constant: a constant assigned inside a describe block is
  # lexically scoped to TOP LEVEL, so it lands on Object and is visible to every
  # other spec in the run.
  let(:auth_env) do
    {
      "SPARC_ENABLE_LOCAL_LOGIN" => "true",
      "SPARC_ENABLE_LDAP"        => "true",
      "SPARC_LDAP_HOST"          => "ldap.example.gov",
      "SPARC_ENABLE_OIDC"        => "true",
      "SPARC_OIDC_PROVIDER_TITLE" => "Okta",
      "SPARC_OIDC_ISSUER_URL"    => "https://dummy.example/oidc",
      "SPARC_OIDC_CLIENT_ID"     => "dummy"
    }
  end

  around do |example|
    original = auth_env.keys.index_with { |key| ENV.fetch(key, nil) }
    auth_env.each { |key, value| ENV[key] = value }
    example.run
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "blocks the login form behind the mandatory consent banner until Proceed (#190)" do
    visit "/login"
    # Consent modal is shown on load; the login card is hidden (d-none) and
    # its controls are not reachable until the user consents.
    expect(page).to have_button("Proceed")
    expect(page).to have_no_button("Local Login")

    accept_consent_banner

    # Proceeding reveals the login card and its tabs.
    expect(page).to have_button("Local Login")
    expect(page).to have_button("LDAP")
  end

  it "renders both form tabs and the Local panel is visible on first load" do
    visit "/login"
    accept_consent_banner
    expect(page).to have_button("Local Login")
    expect(page).to have_button("LDAP")
    expect(page).to have_css("#tab-local.active")
    expect(page).not_to have_css("#tab-ldap.active")
  end

  it "switching to the LDAP tab swaps panel visibility (the CSP regression case)" do
    visit "/login"
    accept_consent_banner
    click_button "LDAP"
    # If inline onclick handlers were blocked (the v1.7.0 → v1.8.0
    # regression), this expectation fails because switchTab never
    # fires and the panel-active class never moves to the other panel.
    expect(page).to have_css("#tab-ldap.active", wait: 2)
    expect(page).not_to have_css("#tab-local.active")
    expect(page).to have_button("Sign In with LDAP")
  end

  it "switching back to Local restores the Local panel" do
    visit "/login"
    accept_consent_banner
    click_button "LDAP"
    expect(page).to have_css("#tab-ldap.active", wait: 2)

    click_button "Local Login"
    expect(page).to have_css("#tab-local.active", wait: 2)
    expect(page).not_to have_css("#tab-ldap.active")
  end

  # #1082, proved in a real browser rather than only in the rendered markup:
  # the provider is reachable from the page you land on, with no tab in between.
  it "offers the OIDC provider as a button on the landing view, not behind a tab" do
    visit "/login"
    accept_consent_banner

    expect(page).to have_button("Sign in with Okta")
    expect(page).not_to have_css('[data-tab="tab-oidc"]')
  end
end
