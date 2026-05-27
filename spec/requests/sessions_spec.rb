# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  before do
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "GET /login" do
    it "renders the login page" do
      get login_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects to root if already signed in" do
      user = create(:user)
      post login_path, params: { email: user.email, password: "SecurePassword123!" }
      get login_path
      expect(response).to redirect_to(root_path)
    end

    context "when consent banner is enabled with a valid file" do
      let(:banner_file) { Tempfile.new([ "banner", ".html" ]) }

      before do
        banner_file.write("<p>You must accept this warning to continue.</p>")
        banner_file.rewind
        allow(SparcConfig).to receive(:banner_enabled?).and_return(true)
        allow(SparcConfig).to receive(:banner_message_path).and_return(banner_file.path)
      end

      after { banner_file.unlink }

      it "includes the consent banner modal" do
        get login_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("consentBannerLabel")
        expect(response.body).to include("You must accept this warning to continue.")
      end

      it "hides the login card initially" do
        get login_path
        expect(response.body).to include('d-none')
        expect(response.body).to include('consent-banner-target="loginCard"')
      end
    end

    context "when consent banner is enabled but file is missing" do
      before do
        allow(SparcConfig).to receive(:banner_enabled?).and_return(true)
        allow(SparcConfig).to receive(:banner_message_path).and_return("/nonexistent/path.html")
      end

      it "renders the login page without banner" do
        get login_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("consentBannerLabel")
      end
    end

    context "when consent banner is enabled but path is not set" do
      before do
        allow(SparcConfig).to receive(:banner_enabled?).and_return(true)
        allow(SparcConfig).to receive(:banner_message_path).and_return(nil)
      end

      it "renders the login page without banner" do
        get login_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("consentBannerLabel")
      end
    end

    context "when consent banner is disabled" do
      before do
        allow(SparcConfig).to receive(:banner_enabled?).and_return(false)
      end

      it "does not include the consent banner" do
        get login_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("consentBannerLabel")
      end
    end

    context "when consent banner file contains unsafe HTML" do
      let(:banner_file) { Tempfile.new([ "banner", ".html" ]) }

      before do
        banner_file.write('<p>Safe content</p><script>alert("xss")</script>')
        banner_file.rewind
        allow(SparcConfig).to receive(:banner_enabled?).and_return(true)
        allow(SparcConfig).to receive(:banner_message_path).and_return(banner_file.path)
      end

      after { banner_file.unlink }

      it "strips script tags from the banner content" do
        get login_path
        # The banner area in the modal body should have the safe content
        # but the <script> tag itself is stripped (text content may remain as inert text)
        expect(response.body).to include("Safe content")
        expect(response.body).not_to include("<script>alert")
      end
    end
  end

  describe "POST /login" do
    let!(:user) { create(:user, email: "jane@example.com", password: "SecurePassword123!", password_confirmation: "SecurePassword123!") }

    context "with valid credentials" do
      it "signs in the user and redirects to root" do
        post login_path, params: { email: "jane@example.com", password: "SecurePassword123!" }
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Signed in successfully")
      end

      it "creates an audit event" do
        expect {
          post login_path, params: { email: "jane@example.com", password: "SecurePassword123!" }
        }.to change(AuditEvent, :count).by(1)

        event = AuditEvent.last
        expect(event.action).to eq("login_success")
        expect(event.provider).to eq("local")
      end
    end

    context "with invalid credentials" do
      it "renders login page with error" do
        post login_path, params: { email: "jane@example.com", password: "wrongpassword!" }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "logs failed attempt" do
        expect {
          post login_path, params: { email: "jane@example.com", password: "wrongpassword!" }
        }.to change(AuditEvent, :count).by(1)

        event = AuditEvent.last
        expect(event.action).to eq("login_failure")
      end
    end

    context "with case-insensitive email" do
      it "finds user regardless of email casing" do
        post login_path, params: { email: "JANE@Example.COM", password: "SecurePassword123!" }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when local login is disabled" do
      before { allow(SparcConfig).to receive(:enable_local_login?).and_return(false) }

      it "redirects with error" do
        post login_path, params: { email: "jane@example.com", password: "SecurePassword123!" }
        expect(response).to redirect_to(login_path)
      end
    end

    context "with suspended user" do
      let!(:suspended_user) { create(:user, :suspended, email: "suspended@example.com") }

      it "rejects login for suspended users" do
        post login_path, params: { email: "suspended@example.com", password: "SecurePassword123!" }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /logout" do
    it "signs out the user" do
      user = create(:user)
      post login_path, params: { email: user.email, password: "SecurePassword123!" }
      delete logout_path
      expect(response).to redirect_to(root_path)
    end

    it "creates a logout audit event" do
      user = create(:user)
      post login_path, params: { email: user.email, password: "SecurePassword123!" }

      expect {
        delete logout_path
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.action).to eq("logout")
    end
  end

  # ── v1.8.1 — Okta/OIDC tab CSP regression (#hotfix) ───────────────────
  describe "login page tab toggle (CSP regression guard)" do
    before do
      allow(SparcConfig).to receive(:enable_oidc?).and_return(true)
      allow(SparcConfig).to receive(:oidc_provider_title).and_return("Okta")
    end

    it "renders tab buttons with data-tab attributes (not inline onclick)" do
      get login_path
      expect(response.body).to include('data-tab="tab-local"')
      expect(response.body).to include('data-tab="tab-oidc"')
      # Inline onclick handlers are blocked by CSP (no 'unsafe-inline');
      # if any tab button regresses to inline onclick the toggle silently dies.
      expect(response.body).not_to match(/<button[^>]*data-tab[^>]*onclick=/)
    end

    it "wires the click delegation in the nonce'd <script> block" do
      get login_path
      expect(response.body).to match(/<script\s+nonce=".+?">[^<]*addEventListener\('click'/m)
    end

    it "shows the OIDC tab when OIDC is enabled" do
      get login_path
      expect(response.body).to include("Sign in with Okta")
    end
  end

  # ── #587 — login_failure reason capture ────────────────────────────
  describe "POST /login failure-reason audit metadata (#587)" do
    it "records reason: invalid_password when the password is wrong" do
      user = create(:user, status: "active")
      expect {
        post login_path, params: { email: user.email, password: "wrong" }
      }.to change { AuditEvent.where(action: "login_failure").count }.by(1)

      event = AuditEvent.where(action: "login_failure").last
      expect(event.metadata["reason"]).to eq("invalid_password")
      expect(event.metadata["auth_method"]).to eq("local")
    end

    it "records reason: unknown_email when no user matches" do
      post login_path, params: { email: "ghost-#{SecureRandom.hex(4)}@nowhere.test", password: "anything" }
      event = AuditEvent.where(action: "login_failure").last
      expect(event.metadata["reason"]).to eq("unknown_email")
      expect(event.metadata["auth_method"]).to eq("local")
    end

    it "records reason: no_local_password when the user is OAuth-only" do
      user = create(:user)
      user.update_column(:password_digest, nil)
      post login_path, params: { email: user.email, password: "anything" }
      event = AuditEvent.where(action: "login_failure").last
      expect(event.metadata["reason"]).to eq("no_local_password")
    end

    it "records reason: account_deactivated for the deactivated short-circuit" do
      user = create(:user, status: "active")
      allow_any_instance_of(User).to receive(:deactivated?).and_return(true)
      post login_path, params: { email: user.email, password: "SecurePassword123!" }
      event = AuditEvent.where(action: "login_failure").last
      expect(event.metadata["reason"]).to eq("account_deactivated")
      expect(event.metadata["auth_method"]).to eq("local")
    end

    it "user-facing flash stays generic even when reason is specific" do
      post login_path, params: { email: "ghost-#{SecureRandom.hex(4)}@nowhere.test", password: "x" }
      expect(flash[:error]).to eq("Invalid email or password.")
    end

    it "tags login_success events with auth_method=local" do
      user = create(:user, status: "active")
      post login_path, params: { email: user.email, password: "SecurePassword123!" }
      event = AuditEvent.where(action: "login_success").last
      expect(event.metadata["auth_method"]).to eq("local")
    end
  end
end
