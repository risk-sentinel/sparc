# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Users", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "GET /api/v1/users" do
    it "returns 200 with user list for admin" do
      create_list(:user, 3)

      get api_v1_users_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]).to be_an(Array)
      expect(parsed["data"].length).to be >= 3
      expect(parsed["meta"]).to include("page", "count")
    end

    it "returns 401 without a token" do
      get api_v1_users_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:id" do
    it "returns user details as admin" do
      target_user = create(:user)

      get api_v1_user_path(target_user), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(target_user.id)
      expect(parsed["data"]["email"]).to eq(target_user.email)
    end

    context "as a non-admin" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns own details" do
        get api_v1_user_path(regular_user), headers: user_headers
        expect(response).to have_http_status(:ok)

        parsed = JSON.parse(response.body)
        expect(parsed["data"]["id"]).to eq(regular_user.id)
      end

      it "returns 403 when accessing a different user" do
        other_user = create(:user)

        get api_v1_user_path(other_user), headers: user_headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/users" do
    it "creates a user as admin" do
      auth_headers # force-create admin user before counting

      user_params = {
        user: {
          email: "newuser@example.com",
          password: "SecurePassword123!",
          password_confirmation: "SecurePassword123!",
          first_name: "New",
          last_name: "User",
          display_name: "New User"
        }
      }

      expect {
        post api_v1_users_path, params: user_params, headers: auth_headers, as: :json
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["email"]).to eq("newuser@example.com")
    end

    context "as a non-admin" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        post api_v1_users_path, params: { user: { email: "test@example.com", password: "Pwd123!", password_confirmation: "Pwd123!" } },
             headers: user_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /api/v1/users/:id" do
    it "updates a user as admin" do
      target_user = create(:user)

      patch api_v1_user_path(target_user),
            params: { user: { display_name: "Updated Name" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["display_name"]).to eq("Updated Name")
    end
  end

  describe "DELETE /api/v1/users/:id" do
    it "deactivates a user as admin" do
      target_user = create(:user)

      delete api_v1_user_path(target_user), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["status"]).to eq("deactivated")
      expect(target_user.reload.status).to eq("deactivated")
    end

    context "as a non-admin" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        other_user = create(:user)

        delete api_v1_user_path(other_user), headers: user_headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
