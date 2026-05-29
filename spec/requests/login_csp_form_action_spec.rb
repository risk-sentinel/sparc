# frozen_string_literal: true

require "rails_helper"

# #593 — The login page initiates SSO via same-origin POST forms to
# /auth/:provider, which OmniAuth answers with a 302 to the external IdP.
# Chromium enforces the CSP `form-action` directive against every hop in that
# redirect chain, so the IdP origin must be allowlisted or the OAuth button is
# silently blocked (Firefox does not re-check redirects, which masked the bug).
#
# SessionsController#new relaxes form-action to the enabled IdP origins on the
# login page ONLY; every other page keeps the strict global 'self' policy.
RSpec.describe "Login page CSP form-action (#593)", type: :request do
  around do |ex|
    keys = %w[SPARC_GITHUB_CLIENT_ID SPARC_ENABLE_OIDC SPARC_OIDC_ISSUER_URL
              SPARC_OIDC_CLIENT_ID SPARC_OIDC_PROVIDER_TITLE]
    saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
    ex.run
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def form_action_directive
    csp = response.headers["Content-Security-Policy"].to_s
    csp[/form-action[^;]*/]
  end

  context "with GitHub and OIDC (Okta) enabled" do
    before do
      ENV["SPARC_GITHUB_CLIENT_ID"] = "gh-client"
      ENV["SPARC_ENABLE_OIDC"]      = "true"
      ENV["SPARC_OIDC_ISSUER_URL"]  = "https://acme.okta.com/oauth2/default"
      ENV["SPARC_OIDC_CLIENT_ID"]   = "okta-client"
    end

    it "allows the IdP origins to receive the OAuth POST-redirect" do
      get "/login"
      directive = form_action_directive
      expect(directive).to include("'self'")
      expect(directive).to include("https://github.com")
      expect(directive).to include("https://acme.okta.com")
      # issuer path must NOT leak into the directive — origin only
      expect(directive).not_to include("/oauth2/default")
    end
  end

  context "with no SSO provider enabled" do
    it "keeps form-action restricted to 'self' (no extra origins)" do
      get "/login"
      expect(form_action_directive).to match(/\Aform-action 'self'\z/)
    end
  end
end
