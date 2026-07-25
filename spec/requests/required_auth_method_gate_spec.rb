# frozen_string_literal: true

require "rails_helper"

# #805 — require phishing-resistant auth. When SPARC_REQUIRE_AUTH_METHODS is set,
# a signed-in user whose session method isn't in the allowlist is bounced to
# /login. Break-glass admin + service accounts exempt. Works app-side (no gateway
# dependency), so "require OIDC or PIV" holds on a single-listener optional mTLS.
RSpec.describe "Required auth-method gate (#805)", type: :request do
  let(:user) { create(:user, email: "human@example.gov") }

  before do
    sign_in_as(user)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  def require_methods(*methods)
    list = methods.flatten
    allow(SparcConfig).to receive(:required_auth_methods).and_return(list)
    allow(SparcConfig).to receive(:require_auth_methods?).and_return(list.any?)
  end

  def as_provider(provider)
    allow_any_instance_of(ApplicationController).to receive(:current_auth_provider).and_return(provider)
  end

  context "when unset (default)" do
    it "imposes no restriction" do
      require_methods
      as_provider("local")
      get root_path
      expect(response).not_to redirect_to(login_path)
    end
  end

  context "require oidc or piv" do
    before { require_methods("oidc", "piv") }

    it "bounces a local-password session to /login" do
      as_provider("local")
      get root_path
      expect(response).to redirect_to(login_path)
    end

    it "allows an OIDC (openid_connect) session" do
      as_provider("openid_connect")
      get root_path
      expect(response).not_to redirect_to(login_path)
    end

    it "allows a PIV session" do
      as_provider("piv")
      get root_path
      expect(response).not_to redirect_to(login_path)
    end

    it "bounces a GitHub SSO session (oidc alias != github)" do
      as_provider("github")
      get root_path
      expect(response).to redirect_to(login_path)
    end

    it "exempts the break-glass bootstrap admin even on local login" do
      admin = create(:user, :admin, email: SparcConfig.admin_email)
      sign_in_as(admin)
      as_provider("local")
      get root_path
      expect(response).not_to redirect_to(login_path)
    end

    it "exempts service accounts" do
      sa = create(:user, service_account: true, owner: create(:user, :admin), email: "svc@service.local")
      sign_in_as(sa)
      as_provider("local")
      get root_path
      expect(response).not_to redirect_to(login_path)
    end
  end

  context "the `sso` alias" do
    before { require_methods("sso") }

    it "accepts any SSO provider (github/gitlab/openid_connect)" do
      as_provider("gitlab")
      get root_path
      expect(response).not_to redirect_to(login_path)
    end

    it "still bounces a local session" do
      as_provider("local")
      get root_path
      expect(response).to redirect_to(login_path)
    end
  end
end
