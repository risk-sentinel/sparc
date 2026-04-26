require "rails_helper"

RSpec.describe AdminCredentialRotationService do
  let(:admin_email) { "admin@sparc.test" }
  let!(:admin) do
    User.create!(email: admin_email, password: "Initial-Pwd-1234",
                 password_confirmation: "Initial-Pwd-1234",
                 admin: true, status: "active", display_name: "Admin")
  end
  let(:actor) { User.create!(email: "ops@sparc.test", password: "Actor-Pwd-1234",
                              password_confirmation: "Actor-Pwd-1234",
                              admin: true, status: "active",
                              display_name: "Ops") }

  before do
    ENV["SPARC_ADMIN_EMAIL"] = admin_email
    ENV.delete("SPARC_ADMIN_CREDENTIALS_SECRET_ARN")
  end

  after do
    ENV.delete("SPARC_ADMIN_EMAIL")
    ENV.delete("SPARC_ADMIN_CREDENTIALS_SECRET_ARN")
  end

  describe ".apply!" do
    it "updates the admin password and writes an audit row" do
      result = described_class.apply!(plaintext: "Brand-New-Password-99",
                                      actor: actor, source: "api")

      expect(result).to be_success
      admin.reload
      expect(admin.authenticate("Brand-New-Password-99")).to be_truthy
      expect(admin.must_reset_password).to eq(true)
      audit = AuditEvent.where(action: "admin_credential_rotated").last
      expect(audit).to be_present
      expect(audit.metadata["source"]).to eq("api")
      expect(audit.metadata["actor_id"]).to eq(actor.id)
    end

    it "rejects passwords shorter than 8 characters" do
      result = described_class.apply!(plaintext: "short", actor: actor, source: "api")
      expect(result).not_to be_success
      expect(result.status_code).to eq(:unprocessable_entity)
    end

    it "returns 404 when the admin email is not present" do
      ENV["SPARC_ADMIN_EMAIL"] = "no-such-admin@sparc.test"
      result = described_class.apply!(plaintext: "Long-Enough-Password-1",
                                      actor: actor, source: "api")
      expect(result).not_to be_success
      expect(result.status_code).to eq(:not_found)
    end

    it "does not push to Secrets Manager when push_to_secrets_manager: false" do
      expect(Aws::SecretsManager::Client).not_to receive(:new)
      described_class.apply!(plaintext: "Brand-New-Password-99",
                             actor: actor, source: "api",
                             push_to_secrets_manager: false)
    end
  end

  describe ".rotate_from_local!" do
    let(:sm_client) { instance_double(Aws::SecretsManager::Client) }

    before do
      ENV["SPARC_ADMIN_CREDENTIALS_SECRET_ARN"] = "arn:aws:secretsmanager:us-east-1:1:secret:sparc-test/admin-credentials-abc"
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(sm_client)
    end

    it "generates a password, pushes to SM, updates DB, and audits" do
      put_response = double("PutResponse", version_id: "v-12345")
      expect(sm_client).to receive(:put_secret_value).with(
        hash_including(secret_id: ENV["SPARC_ADMIN_CREDENTIALS_SECRET_ARN"],
                       version_stages: [ "AWSCURRENT" ])
      ).and_return(put_response)

      result = described_class.rotate_from_local!(actor: actor, source: "rake")

      expect(result).to be_success
      expect(result.version_id).to eq("v-12345")
      expect(result[:plaintext]).to be_a(String)
      expect(result[:plaintext].length).to eq(described_class::PASSWORD_LENGTH)

      admin.reload
      expect(admin.authenticate(result[:plaintext])).to be_truthy
      audit = AuditEvent.where(action: "admin_credential_rotated").last
      expect(audit.metadata["version_id"]).to eq("v-12345")
      expect(audit.metadata["source"]).to eq("rake")
    end

    it "puts JSON-encoded payload with the password key" do
      received_payload = nil
      expect(sm_client).to receive(:put_secret_value) do |args|
        received_payload = JSON.parse(args[:secret_string])
        double("PutResponse", version_id: "v-1")
      end

      described_class.rotate_from_local!(actor: actor, source: "rake")
      expect(received_payload).to have_key("password")
      expect(received_payload["password"].length).to eq(described_class::PASSWORD_LENGTH)
    end

    it "returns failure when SM ARN is unset" do
      ENV.delete("SPARC_ADMIN_CREDENTIALS_SECRET_ARN")
      result = described_class.rotate_from_local!(actor: actor, source: "rake")
      expect(result).not_to be_success
      expect(result.error).to match(/SPARC_ADMIN_CREDENTIALS_SECRET_ARN/)
      expect(admin.reload.authenticate("Initial-Pwd-1234")).to be_truthy
    end

    it "translates AccessDenied to forbidden status without mutating DB" do
      allow(sm_client).to receive(:put_secret_value)
        .and_raise(Aws::SecretsManager::Errors::AccessDeniedException.new(nil, "denied"))

      result = described_class.rotate_from_local!(actor: actor, source: "rake")
      expect(result).not_to be_success
      expect(result.status_code).to eq(:forbidden)
      expect(admin.reload.authenticate("Initial-Pwd-1234")).to be_truthy
    end

    it "translates ResourceNotFound to not_found without mutating DB" do
      allow(sm_client).to receive(:put_secret_value)
        .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, "missing"))

      result = described_class.rotate_from_local!(actor: actor, source: "rake")
      expect(result).not_to be_success
      expect(result.status_code).to eq(:not_found)
      expect(admin.reload.authenticate("Initial-Pwd-1234")).to be_truthy
    end
  end
end
