# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passwords", type: :request do
  let!(:user) { create(:user, :must_reset, email: "admin@sparc.local") }

  before do
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    # Sign in
    post login_path, params: { email: user.email, password: "SecurePassword123!" }
  end

  describe "GET /password/edit" do
    it "renders the password change form" do
      get edit_password_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Change Password")
    end
  end

  describe "PATCH /password" do
    context "with valid current password and new password" do
      it "updates the password and redirects" do
        patch password_path, params: {
          current_password: "SecurePassword123!",
          new_password: "NewSecurePass456!",
          new_password_confirmation: "NewSecurePass456!"
        }
        expect(response).to redirect_to(root_path)
        user.reload
        expect(user.must_reset_password).to be false
        expect(user.password_changed_at).to be_present
      end
    end

    context "with wrong current password" do
      it "renders form with error" do
        patch password_path, params: {
          current_password: "WrongPassword!!!",
          new_password: "NewSecurePass456!",
          new_password_confirmation: "NewSecurePass456!"
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with too-short new password" do
      it "renders form with error" do
        patch password_path, params: {
          current_password: "SecurePassword123!",
          new_password: "short",
          new_password_confirmation: "short"
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
