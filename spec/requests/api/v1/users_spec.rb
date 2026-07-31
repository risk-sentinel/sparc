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

    # #877 — provisioning emits TWO events now: the account was created, and a
    # credential was issued. assert_audit_event requires a delta of exactly 1,
    # so each is asserted directly. Keeping them separate is deliberate: it is
    # what makes "every credential handed to a user" a queryable set.
    it "emits an api_user_created audit event (#433 slice 5)" do
      # #877 — stubbed explicitly rather than relying on the ambient setting:
      # a temporary is only issued when local login is on, and CI runs with it
      # OFF while a dev machine has it ON. Left implicit this passes locally and
      # fails in CI, which is exactly what it did.
      allow(SparcConfig).to receive(:enable_local_login?).and_return(true)

      post api_v1_users_path, params: {
        user: {
          email: "audited@example.com",
          first_name: "Audited",
          last_name: "User",
          display_name: "Audited User"
        }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)

      # This used to be a single assert_audit_event. #877 emits TWO events, and
      # that helper requires a delta of exactly 1 — so both are asserted
      # directly. Asserting only the credential event would leave this example
      # named for a claim it no longer checked.
      #
      # (An earlier comment here said api_user_created was missing from
      # AuditEvent::ACTIONS and silently dropped. That is not true — it is
      # allowlisted, so the event is really written and really assertable.)
      created = AuditEvent.find_by(action: "api_user_created", subject_type: "User")
      expect(created).to be_present
      expect(created.metadata["email"]).to eq("audited@example.com")

      issued = AuditEvent.where(action: "admin_temporary_password_issued").last
      expect(issued).to be_present
      expect(issued.metadata["provisioning"]).to be(true)
    end

    # #877 — the other half of the contract. On an SSO-only instance there is no
    # local credential to issue, so no temporary is generated, nothing is
    # returned, and no issuance is claimed in the audit trail. Worth pinning:
    # the failure that would matter is auditing a credential that was never
    # created, and the account must still be provisioned successfully.
    it "issues no temporary and claims none when local login is disabled" do
      allow(SparcConfig).to receive(:enable_local_login?).and_return(false)

      expect {
        post api_v1_users_path, params: {
          user: {
            email: "sso-only@example.com",
            first_name: "Sso",
            last_name: "Only",
            display_name: "Sso Only"
          }
        }, headers: auth_headers, as: :json
      }.not_to change { AuditEvent.where(action: "admin_temporary_password_issued").count }

      expect(response).to have_http_status(:created)
      expect(User.find_by(email: "sso-only@example.com")).to be_present
      expect(JSON.parse(response.body)["data"]).not_to have_key("temporary_password")
    end

    # The case that exposes why :password must be UNPERMITTED rather than
    # merely overwritten. When local login is on, assign_temporary_password
    # overwrites whatever the caller sent, so a permitted :password is
    # invisible — every assertion still passes. When local login is OFF no
    # temporary is issued at all, nothing overwrites anything, and a permitted
    # :password would be saved verbatim: a credential the provisioning caller
    # chose and knows, on the one deployment shape where SPARC issues none.
    #
    # Verified by mutation: restoring :password to
    # UserProvisioningService::BASE_ATTRIBUTES makes this example fail, and it
    # was the only one that did.
    it "does not let a caller set the password even when none is issued" do
      allow(SparcConfig).to receive(:enable_local_login?).and_return(false)

      post api_v1_users_path, params: {
        user: {
          email: "sso-pw@example.com",
          first_name: "Sso",
          last_name: "Pw",
          password: "CallerChosen123!",
          password_confirmation: "CallerChosen123!"
        }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      created = User.find_by(email: "sso-pw@example.com")
      expect(created.authenticate("CallerChosen123!")).to be_falsey
      expect(created.password_digest).to be_blank
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

    # #877 — see the note on the sibling copy in the other POST block: two
    # audit events are emitted now, so assert_audit_event's exact-delta-of-1
    # no longer fits.
    it "emits an api_user_created audit event (#433 slice 5)" do
      # #877 — see the sibling copy: local login is stubbed explicitly because
      # CI runs with it off and a dev machine runs with it on, and BOTH audit
      # events are asserted directly since assert_audit_event wants a delta of 1.
      allow(SparcConfig).to receive(:enable_local_login?).and_return(true)

      post api_v1_users_path, params: {
        user: {
          email: "audited@example.com",
          first_name: "Audited",
          last_name: "User",
          display_name: "Audited User"
        }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)

      created = AuditEvent.find_by(action: "api_user_created", subject_type: "User")
      expect(created).to be_present
      expect(created.metadata["email"]).to eq("audited@example.com")

      issued = AuditEvent.where(action: "admin_temporary_password_issued").last
      expect(issued).to be_present
      expect(issued.metadata["provisioning"]).to be(true)
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

    it "emits an api_user_updated audit event (#433 slice 5)" do
      target_user = create(:user)
      assert_audit_event(
        action: "api_user_updated",
        subject_type: "User",
        metadata: { email: target_user.email }
      ) do
        patch api_v1_user_path(target_user),
              params: { user: { display_name: "Audited Update" } },
              headers: auth_headers, as: :json
      end
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

    it "emits an api_user_deactivated audit event (#433 slice 5)" do
      target_user = create(:user)
      assert_audit_event(
        action: "api_user_deactivated",
        subject_type: "User",
        metadata: { email: target_user.email }
      ) do
        delete api_v1_user_path(target_user), headers: auth_headers
      end
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
