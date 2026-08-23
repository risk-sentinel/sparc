# frozen_string_literal: true

require "rails_helper"

# #822 — the half that matters: does an IdP-asserted PIV session actually
# SATISFY `SPARC_REQUIRE_AUTH_METHODS=piv`?
#
# PivOidcAssertion decides whether a token proves a smart card was used;
# `check_auth_method` decides whether that counts. Testing only the first would
# leave the feature provably correct and completely inert.
#
# A controller spec rather than a request spec because the assertion lives in
# the session, and this is the level at which a session can be established
# without standing up OmniAuth's middleware for a provider that is not
# registered in the test environment.
RSpec.describe ApplicationController, type: :controller do
  controller do
    def index = render(plain: "ok")
  end

  let(:user) { create(:user) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:require_auth_methods?).and_return(true)
    allow(SparcConfig).to receive(:required_auth_methods).and_return(%w[piv])
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:signed_in?).and_return(true)
  end

  context "an OIDC session with no PIV assertion" do
    it "is refused, because oidc is not piv" do
      session[:user_id] = user.id
      session[:auth_provider] = "oidc"

      get :index

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(login_path)
    end
  end

  context "an OIDC session carrying a PIV assertion" do
    it "satisfies the piv requirement" do
      session[:user_id] = user.id
      session[:auth_provider] = "oidc"
      session[:piv_assertion] = { "amr" => [ "x509" ] }

      get :index

      expect(response).to have_http_status(:ok)
    end

    it "still records the provider as oidc, not piv" do
      # The audit trail has to keep saying HOW the person signed in. Rewriting
      # auth_provider to "piv" would satisfy the gate and lose which IdP the
      # assertion came from.
      session[:user_id] = user.id
      session[:auth_provider] = "oidc"
      session[:piv_assertion] = { "amr" => [ "x509" ] }

      get :index

      expect(session[:auth_provider]).to eq("oidc")
    end
  end

  context "a local session carrying no assertion" do
    it "is still refused" do
      # Guards against the assertion check accidentally becoming unconditional.
      session[:user_id] = user.id
      session[:auth_provider] = "local"

      get :index

      expect(response).to redirect_to(login_path)
    end
  end

  context "when the requirement is not piv" do
    it "an assertion does not let an unrelated method through" do
      allow(SparcConfig).to receive(:required_auth_methods).and_return(%w[webauthn])
      session[:user_id] = user.id
      session[:auth_provider] = "oidc"
      session[:piv_assertion] = { "amr" => [ "x509" ] }

      get :index

      expect(response).to redirect_to(login_path)
    end
  end

  context "the gateway-mTLS path is untouched" do
    it "a piv session still satisfies piv with no assertion present" do
      session[:user_id] = user.id
      session[:auth_provider] = "piv"

      get :index

      expect(response).to have_http_status(:ok)
    end
  end
end
