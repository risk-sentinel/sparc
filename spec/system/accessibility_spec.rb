# frozen_string_literal: true

require "rails_helper"

# Layer 3 of the UI test net (#599) — axe-core accessibility checks against
# real Chrome, scoped to WCAG 2.1 A + AA (the Section 508 conformance bar).
#
# Baseline + ratchet: known violations are skipped via SparcAxe::BASELINE_SKIPS
# (see spec/support/axe_helper.rb) so that NEW accessibility regressions fail
# the build while existing debt is tracked and burned down. This is the Layer 1
# counterpart to tests/ui-smoke/test_accessibility.py.
RSpec.describe "Accessibility (WCAG 2.1 AA)", type: :system do
  it "the login page has no un-baselined violations" do
    ENV["SPARC_ENABLE_LOCAL_LOGIN"] = "true"
    ENV["SPARC_ENABLE_OIDC"]        = "true"
    ENV["SPARC_OIDC_PROVIDER_TITLE"] = "Okta"
    ENV["SPARC_OIDC_ISSUER_URL"]    = "https://dummy.example/oidc"
    ENV["SPARC_OIDC_CLIENT_ID"]     = "dummy"

    visit "/login"
    accept_consent_banner
    expect(page).to have_button("Local Login")

    expect(page).to be_axe_clean
      .according_to(*SparcAxe::WCAG_2_1_AA)
      .skipping(*SparcAxe.baseline_for(:login))
  end
end
