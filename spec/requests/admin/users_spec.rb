# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  def valid_params(overrides = {})
    {
      user: {
        email: "created@example.com",
        password: "SecurePassword123!",
        password_confirmation: "SecurePassword123!",
        first_name: "Created",
        last_name: "User",
        display_name: "Created User",
        status: "active"
      }.merge(overrides)
    }
  end

  describe "authorization" do
    it "redirects a non-admin away from the new form" do
      sign_in_as(regular_user)
      get new_admin_user_path
      expect(response).to redirect_to(root_path)
    end

    it "blocks a non-admin from creating a user" do
      sign_in_as(regular_user)
      expect {
        post admin_users_path, params: valid_params
      }.not_to change(User, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/users/new" do
    before { sign_in_as(admin) }

    it "renders the create-user form" do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New User")
      expect(response.body).to include("Create User")
    end
  end

  describe "POST /admin/users" do
    before { sign_in_as(admin) }

    it "creates an active user and redirects to the show page" do
      expect {
        post admin_users_path, params: valid_params
      }.to change(User, :count).by(1)

      user = User.find_by(email: "created@example.com")
      expect(user).to be_present
      expect(user.status).to eq("active")
      expect(user.admin).to be(false)
      expect(response).to redirect_to(admin_user_path(user))
    end

    it "emits a user_created audit event" do
      assert_audit_event(
        action: "user_created",
        subject_type: "User",
        metadata: { target_email: "created@example.com" }
      ) do
        post admin_users_path, params: valid_params
      end
    end

    it "lets an admin create another admin" do
      post admin_users_path, params: valid_params(admin: "1")
      expect(User.find_by(email: "created@example.com").admin).to be(true)
    end

    it "assigns selected instance roles" do
      role = create(:role, scope: "instance", display_name: "ISSO")
      post admin_users_path, params: valid_params(role_ids: [ role.id.to_s ])
      user = User.find_by(email: "created@example.com")
      expect(user.user_roles.where(authorization_boundary_id: nil).pluck(:role_id)).to include(role.id)
    end

    context "validation failures" do
      it "rejects a password shorter than 12 characters" do
        expect {
          post admin_users_path, params: valid_params(password: "short", password_confirmation: "short")
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("at least 12 characters")
      end

      it "rejects a duplicate email" do
        create(:user, email: "created@example.com")
        expect {
          post admin_users_path, params: valid_params
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
