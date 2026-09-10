# frozen_string_literal: true

require "rails_helper"

# #1082 — what the login page OFFERS must match what the #805 gate ACCEPTS.
#
# Asserts on response.body rather than on config predicates: the whole failure
# was a page rendering a method the gate would refuse, and a config-only spec
# cannot see the page.
RSpec.describe "Login page offers (#1082)", type: :request do
  before { allow(SparcConfig).to receive(:enable_registration?).and_return(false) }

  describe "OIDC is a button, not a tab" do
    before do
      allow(SparcConfig).to receive_messages(
        enable_local_login?: true, enable_oidc?: true,
        oidc_client_id: "abc123", oidc_provider_title: "Okta",
        require_auth_methods?: false, required_auth_methods: []
      )
    end

    it "puts the provider button one click away, in the same stack as the other SSO methods" do
      get login_path

      expect(response.body).to include("Sign in with Okta")
    end

    # The two-click problem: OIDC was the only SSO method rendered as a tab, and
    # its entire panel was one button. FIDO2, PIV, GitHub and GitLab were never
    # tabs. Reaching Okta meant selecting a tab and then pressing the button.
    it "no longer renders an OIDC tab" do
      get login_path

      expect(response.body).not_to include('data-tab="tab-oidc"')
    end

    it "renders no tab bar at all when local login is the only form-based method" do
      get login_path

      expect(response.body).not_to include('role="tablist"')
    end

    it "still renders the local email and password form" do
      get login_path

      expect(response.body).to include('name="password"')
    end
  end

  describe "when a required-methods policy excludes local login" do
    before do
      allow(SparcConfig).to receive_messages(
        enable_local_login?: true, enable_oidc?: true,
        oidc_client_id: "abc123", oidc_provider_title: "Okta",
        require_auth_methods?: true, required_auth_methods: [ "oidc" ]
      )
    end

    it "tells the user what their organization requires" do
      get login_path

      expect(response.body).to include("Your organization requires signing in with")
    end

    it "offers the required method" do
      get login_path

      expect(response.body).to include("Sign in with Okta")
    end

    # The break-glass bootstrap admin is EXEMPT from the #805 gate
    # (auth_gate_exempt_user?). Hiding the password form outright would leave
    # that account no way in — during an IdP outage, which is precisely when it
    # is needed. So it is demoted, never removed.
    it "keeps a break-glass password form reachable" do
      get login_path

      expect(response.body).to include("Administrator sign-in")
      expect(response.body).to include('name="password"')
    end

    it "says plainly that an ordinary account cannot hold a session with it" do
      get login_path

      expect(response.body).to match(/signed out again immediately/i)
    end

    # Asserts on the PANEL, not the tab button. With one form-based method no
    # tab bar renders at all, so a `data-tab` assertion passes whether or not
    # the policy was honoured — it cannot tell the two apart. The panel id only
    # appears when local login is offered as an ordinary method.
    it "does not present local login as an ordinary panel" do
      get login_path

      expect(response.body).not_to include('id="tab-local"')
    end
  end

  describe "when the policy demands a method the instance cannot offer" do
    before do
      allow(SparcConfig).to receive_messages(
        enable_local_login?: false, enable_oidc?: false, oidc_client_id: nil,
        require_auth_methods?: true, required_auth_methods: [ "oidc" ]
      )
    end

    # Production raises at boot (zz_auth_posture.rb) and never reaches this. In
    # development it must still SAY what is wrong rather than showing an empty
    # box, which is the same silent-failure shape as #978.
    it "names the misconfiguration instead of rendering an empty page" do
      get login_path

      expect(response.body).to include("No Usable Sign-In Method")
      expect(response.body).to include("SPARC_REQUIRE_AUTH_METHODS")
    end
  end

  describe "when nothing is configured at all" do
    before do
      allow(SparcConfig).to receive_messages(
        enable_local_login?: false, enable_oidc?: false, oidc_client_id: nil,
        enable_ldap?: false, enable_piv?: false, fido2_enabled?: false,
        github_enabled?: false, gitlab_enabled?: false,
        require_auth_methods?: false, required_auth_methods: []
      )
    end

    it "keeps the original not-configured message" do
      get login_path

      expect(response.body).to include("Authentication Not Configured")
    end
  end
end
