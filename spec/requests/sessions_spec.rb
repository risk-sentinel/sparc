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
end
