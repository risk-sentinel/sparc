# frozen_string_literal: true

require "rails_helper"

# #802 — mandatory FIDO2 enrollment gate. When SPARC_REQUIRE_FIDO2 is on, a
# signed-in user with no security key is forced to the enrollment page before
# reaching anything else. Mirrors check_password_reset.
RSpec.describe "Mandatory FIDO2 enrollment gate (#802)", type: :request do
  let(:user) { create(:user, email: "human@example.gov") }

  before do
    sign_in_as(user)
    # Layout renders auth-gated nav; CI lacks SPARC_ENABLE_* (feedback_local_env_vs_ci_drift).
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  # Stubbing require_fido2_mode cascades to require_fido2? and fido2_enabled?.
  def set_mode(mode)
    allow(SparcConfig).to receive(:require_fido2_mode).and_return(mode)
  end

  def as_provider(provider)
    allow_any_instance_of(ApplicationController).to receive(:current_auth_provider).and_return(provider)
  end

  context "when the gate is off (default)" do
    it "does not redirect a keyless user" do
      set_mode("off")
      get root_path
      expect(response).not_to redirect_to(webauthn_credentials_path)
    end
  end

  context "mode = all" do
    before { set_mode("all") }

    it "redirects a keyless human user to enrollment" do
      get root_path
      expect(response).to redirect_to(webauthn_credentials_path)
    end

    it "lets a user who already has a key through" do
      create(:webauthn_credential, user: user)
      get root_path
      expect(response).not_to redirect_to(webauthn_credentials_path)
    end

    it "exempts service accounts (humanless)" do
      sa = create(:user, service_account: true, owner: create(:user, :admin), email: "svc@service.local")
      sign_in_as(sa)
      get root_path
      expect(response).not_to redirect_to(webauthn_credentials_path)
    end

    it "exempts the break-glass bootstrap admin (admin_email)" do
      break_glass = create(:user, :admin, email: SparcConfig.admin_email)
      sign_in_as(break_glass)
      get root_path
      expect(response).not_to redirect_to(webauthn_credentials_path)
    end

    it "STILL gates a human admin that is not the break-glass account" do
      human_admin = create(:user, :admin, email: "real.admin@example.gov")
      sign_in_as(human_admin)
      get root_path
      expect(response).to redirect_to(webauthn_credentials_path)
    end

    it "does not loop — the enrollment page itself is reachable" do
      get webauthn_credentials_path
      expect(response).not_to redirect_to(webauthn_credentials_path)
      expect(response).to have_http_status(:ok)
    end

    it "keeps logout reachable so a gated user can escape" do
      delete logout_path
      expect(response).not_to redirect_to(webauthn_credentials_path)
    end

    it "gates an OIDC session too (all = every auth method)" do
      as_provider("oidc")
      get root_path
      expect(response).to redirect_to(webauthn_credentials_path)
    end
  end

  context "mode = local" do
    before { set_mode("local") }

    it "gates a local-password session" do
      as_provider("local")
      get root_path
      expect(response).to redirect_to(webauthn_credentials_path)
    end

    it "exempts an OIDC/LDAP session (their IdP handles MFA)" do
      as_provider("oidc")
      get root_path
      expect(response).not_to redirect_to(webauthn_credentials_path)
    end
  end

  context "post-recovery (admin reset the user's keys, #779)" do
    before { set_mode("all") }

    it "re-forces enrollment once the user has zero keys again" do
      cred = create(:webauthn_credential, user: user)
      get root_path
      expect(response).not_to redirect_to(webauthn_credentials_path)

      cred.destroy! # admin reset_security_keys leaves zero keys
      get root_path
      expect(response).to redirect_to(webauthn_credentials_path)
    end
  end
end
