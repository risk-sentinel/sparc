# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Registrations", type: :request do
  before do
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    allow(SparcConfig).to receive(:enable_registration?).and_return(true)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "GET /register" do
    it "renders the registration form" do
      get register_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create Your Account")
    end

    context "when registration is disabled" do
      before { allow(SparcConfig).to receive(:enable_registration?).and_return(false) }

      it "redirects to login" do
        get register_path
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "POST /register" do
    let(:valid_params) do
      {
        user: {
          email: "newuser@example.com",
          password: "SecurePassword123!",
          password_confirmation: "SecurePassword123!",
          first_name: "Jane",
          last_name: "Doe"
        }
      }
    end

    context "with valid params" do
      it "creates a user and signs in" do
        expect {
          post register_path, params: valid_params
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(root_path)

        user = User.last
        expect(user.email).to eq("newuser@example.com")
        expect(user.first_name).to eq("Jane")
        expect(user.status).to eq("active")
        expect(user.admin).to be false
      end

      it "normalizes email casing" do
        post register_path, params: {
          user: valid_params[:user].merge(email: "JANE.DOE@AOL.COM")
        }
        expect(User.last.email).to eq("jane.doe@aol.com")
      end

      it "creates an audit event" do
        expect {
          post register_path, params: valid_params
        }.to change(AuditEvent, :count).by(1)
      end
    end

    context "with invalid params" do
      it "rejects short passwords" do
        post register_path, params: {
          user: valid_params[:user].merge(password: "short", password_confirmation: "short")
        }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(User.count).to eq(0)
      end

      it "rejects mismatched passwords" do
        post register_path, params: {
          user: valid_params[:user].merge(password_confirmation: "DifferentPassword!")
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects duplicate emails" do
        create(:user, email: "newuser@example.com")
        post register_path, params: valid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when registration is disabled" do
      before { allow(SparcConfig).to receive(:enable_registration?).and_return(false) }

      it "redirects to login" do
        post register_path, params: valid_params
        expect(response).to redirect_to(login_path)
        expect(User.count).to eq(0)
      end
    end
  end
end
