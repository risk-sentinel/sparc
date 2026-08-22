# frozen_string_literal: true

require "rails_helper"

# #995 — `POST /api/v1/users/:id/password_reset` (#841) had no test at all.
#
# It is the one endpoint that mints a credential. The properties that matter are
# not the 201: that the emailed token is NOT in the response, that the temporary
# password forces a change so the credential the admin necessarily saw does not
# survive, and that only an admin can call it.
RSpec.describe "Api::V1 user password reset", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:target) { create(:user) }
  let(:path) { "/api/v1/users/#{target.id}/password_reset" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end
  let(:admin_headers) { headers_for(admin) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "mode=temporary (the default)" do
    it "issues a temporary password and returns it once" do
      post path, headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["mode"]).to eq("temporary")
      expect(data["temporary_password"]).to be_present
      expect(data["must_change_at_next_login"]).to be(true)
    end

    it "issues a password that actually authenticates" do
      post path, headers: admin_headers, as: :json
      issued = response.parsed_body["data"]["temporary_password"]

      expect(target.reload.authenticate(issued)).to be_truthy,
        "the returned string is not the password that was set, so it is useless to the user"
    end

    it "forces a change at next sign-in, so the credential the admin saw does not survive" do
      post path, headers: admin_headers, as: :json

      expect(target.reload.must_reset_password).to be(true)
    end

    it "does not leave a lingering email-reset token behind" do
      target.issue_password_reset!

      post path, headers: admin_headers, as: :json

      expect(target.reload.password_reset_digest).to be_nil
    end

    it "records an audit event naming the target" do
      expect { post path, headers: admin_headers, as: :json }
        .to change { AuditEvent.where(action: "admin_temporary_password_issued").count }.by(1)

      expect(AuditEvent.where(action: "admin_temporary_password_issued").last.metadata["target_user_id"])
        .to eq(target.id)
    end
  end

  describe "mode=email" do
    before { allow(SparcConfig).to receive(:enable_smtp?).and_return(true) }

    # The property this mode exists for. Emailing a token AND returning it would
    # defeat the point of sending it to the mailbox owner.
    #
    # What can leak is the PLAINTEXT token, so the plaintext is what this has to
    # search for. Comparing against `password_reset_digest` proved nothing: the
    # database keeps a SHA-256 and the response could not have contained it
    # however badly the endpoint behaved.
    #
    # The producer is stubbed to mint a known sentinel -- the controller is left
    # exactly as it ships -- and the mailer assertion proves the endpoint really
    # held that sentinel, so a body without it is a result rather than a stub
    # that quietly failed to take.
    it "never returns the token" do
      sentinel = "SENTINEL-PLAINTEXT-#{SecureRandom.hex(8)}"
      allow_any_instance_of(User).to receive(:issue_password_reset!) do |user|
        user.update!(password_reset_digest: Digest::SHA256.hexdigest(sentinel),
                     password_reset_expires_at: 1.hour.from_now)
        sentinel
      end
      allow(PasswordResetMailer).to receive(:reset_link).and_call_original

      post path, params: { mode: "email" }, headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(PasswordResetMailer).to have_received(:reset_link).with(target, sentinel, issued_by: admin.email),
        "the endpoint never held the sentinel, so searching the body for it would assert nothing"

      expect(response.body).not_to include(sentinel)
      # An exact key set, not a list of names to avoid: a token surfaced under
      # any other key is the same leak.
      expect(response.parsed_body["data"].keys)
        .to match_array(%w[user_id email mode expires_at note])
    end

    it "issues a reset with an expiry the caller can see" do
      post path, params: { mode: "email" }, headers: admin_headers, as: :json

      expect(response.parsed_body["data"]["expires_at"]).to be_present
      expect(target.reload.password_reset_expires_at).to be_present
    end

    it "sends the mail" do
      expect {
        post path, params: { mode: "email" }, headers: admin_headers, as: :json
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    it "does not force a password change, since the user chooses their own" do
      post path, params: { mode: "email" }, headers: admin_headers, as: :json

      expect(target.reload.must_reset_password).to be(false)
    end

    it "refuses when no mail is configured, naming the alternative" do
      allow(SparcConfig).to receive(:enable_smtp?).and_return(false)

      post path, params: { mode: "email" }, headers: admin_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/temporary/)
      expect(target.reload.password_reset_digest).to be_nil,
        "a refused request still issued a reset"
    end
  end

  describe "refusals" do
    it "refuses an unknown mode by name, without issuing anything" do
      post path, params: { mode: "carrier_pigeon" }, headers: admin_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/carrier_pigeon/)
      expect(target.reload.must_reset_password).to be(false)
    end

    # AC-2 — the lifecycle statuses are active / suspended / deactivated. A
    # credential must not be minted for an account that is not active, or a
    # suspension could be undone by resetting the password.
    %w[suspended deactivated].each do |status|
      it "refuses to reset a #{status} user" do
        target.update!(status: status)

        post path, headers: admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to match(/active/i)
        expect(target.reload.must_reset_password).to be(false)
      end
    end

    it "404s for a user that does not exist" do
      post "/api/v1/users/0/password_reset", headers: admin_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authorization" do
    it "refuses a non-admin" do
      post path, headers: headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(target.reload.must_reset_password).to be(false)
    end

    # Minting yourself a fresh credential is exactly what an attacker with a
    # stolen token would try. Being the target is not authority to reset.
    it "refuses a non-admin resetting their own password" do
      post "/api/v1/users/#{target.id}/password_reset", headers: headers_for(target), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an anonymous caller" do
      post path, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
