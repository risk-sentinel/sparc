# frozen_string_literal: true

require "rails_helper"

# #877 — SPARC already had a correct forced-reset credential handover
# (issue_temporary_password!, used by the admin reset flow). Provisioning did
# not use it: the admin typed a password into the new-user form and the user was
# never made to replace it. A credential the admin chose, knew, and which
# survived indefinitely — password_expired? could not catch it either, because
# it returns false when password_changed_at is blank, which is exactly the state
# a freshly provisioned account is in.
#
# This matters most in the configuration where provisioning is the ONLY way to
# get an account: local registration disabled.
RSpec.describe "Admin-provisioned credentials (#877)", type: :request do
  let(:admin) { create(:user, admin: true, email: "admin@example.gov") }

  before do
    sign_in_as(admin)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  def provision(email: "newuser@example.gov")
    post admin_users_path, params: {
      user: { email: email, first_name: "New", last_name: "User", status: "active" }
    }
  end

  describe "the web UI" do
    it "creates the user without the admin choosing a password" do
      expect { provision }.to change(User, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "forces the password to be changed at first sign-in" do
      provision

      expect(User.find_by(email: "newuser@example.gov").must_reset_password).to be(true)
    end

    it "hands the temporary over once, through the flash" do
      provision

      expect(flash[:temporary_password]).to be_present
      expect(flash[:temporary_password].length).to be >= 16
    end

    it "leaves password_changed_at unset so the credential reads as never chosen by the user" do
      provision

      expect(User.find_by(email: "newuser@example.gov").password_changed_at).to be_nil
    end

    it "audits it the same way a reset is audited" do
      provision

      expect(AuditEvent.where(action: "admin_temporary_password_issued")).to exist
    end

    it "no longer asks the admin to type a password" do
      get new_admin_user_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("input[name='user[password]']")).to be_empty
      expect(doc.css("input[name='user[password_confirmation]']")).to be_empty
    end

    it "tells the admin a temporary will be generated" do
      get new_admin_user_path

      expect(response.body).to match(/temporary password will be generated/i)
    end
  end

  describe "the temporary actually gates the user" do
    it "sends them to the password screen on their first request" do
      provision
      temporary = flash[:temporary_password]
      new_user = User.find_by(email: "newuser@example.gov")

      # The temporary authenticates...
      expect(new_user.authenticate(temporary)).to be_truthy

      # ...but must_reset_password diverts them until they replace it.
      sign_in_as(new_user)
      get admin_users_path
      expect(response).to redirect_to(edit_password_path)
    end
  end

  describe "the API behaves identically" do
    let(:token) { ApiToken.generate!(user: admin, name: "provisioning-spec").plaintext_token }

    def provision_api(email: "apiuser@example.gov")
      post "/api/v1/users",
           params: { user: { email: email, first_name: "Api", last_name: "User" } },
           headers: { "Authorization" => "Bearer #{token}" }
    end

    it "returns the temporary once in the create response" do
      provision_api

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "temporary_password")).to be_present
    end

    it "forces the reset, exactly as the UI does" do
      provision_api

      expect(User.find_by(email: "apiuser@example.gov").must_reset_password).to be(true)
    end

    it "never exposes the temporary again on a later read" do
      provision_api
      created = User.find_by(email: "apiuser@example.gov")

      get "/api/v1/users/#{created.id}", headers: { "Authorization" => "Bearer #{token}" }

      expect(response.parsed_body["data"]).not_to have_key("temporary_password")
    end
  end

  describe "when local login is disabled" do
    before { allow(SparcConfig).to receive(:enable_local_login?).and_return(false) }

    it "issues no credential — the user arrives through the identity provider" do
      expect { provision }.to change(User, :count).by(1)

      expect(flash[:temporary_password]).to be_nil
      expect(User.find_by(email: "newuser@example.gov").must_reset_password).to be_falsey
    end

    it "says so on the form rather than promising a password that never comes" do
      get new_admin_user_path

      expect(response.body).to match(/Local login is disabled/i)
    end
  end
end
