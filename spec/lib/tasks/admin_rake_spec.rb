require "rails_helper"
require "rake"

RSpec.describe "lib/tasks/admin.rake", type: :task do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task) { Rake::Task["sparc:bootstrap_admin"] }
  let(:email) { "admin@sparc.test" }

  before do
    task.reenable
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    ENV["SPARC_ADMIN_EMAIL"] = email
    ENV.delete("SPARC_ADMIN_PASSWORD")
  end

  after do
    ENV.delete("SPARC_ADMIN_EMAIL")
    ENV.delete("SPARC_ADMIN_PASSWORD")
  end

  describe "first boot" do
    it "creates the admin with a generated password when SPARC_ADMIN_PASSWORD is unset" do
      expect { task.invoke }.to change { User.where(email: email).count }.by(1)
      admin = User.find_by(email: email)
      expect(admin.admin?).to eq(true)
      expect(admin.must_reset_password).to eq(true)
      expect(admin.password_digest).to be_present
    end

    it "creates the admin using SPARC_ADMIN_PASSWORD when set" do
      ENV["SPARC_ADMIN_PASSWORD"] = "Injected-From-SM-1234"
      task.invoke
      admin = User.find_by(email: email)
      expect(admin).to be_present
      expect(admin.authenticate("Injected-From-SM-1234")).to be_truthy
    end

    it "audits the bootstrap event with source metadata" do
      ENV["SPARC_ADMIN_PASSWORD"] = "Injected-From-SM-1234"
      expect {
        task.invoke
      }.to change { AuditEvent.where(action: "admin_bootstrap").count }.by(1)
      event = AuditEvent.where(action: "admin_bootstrap").last
      expect(event.metadata["source"]).to eq("ecs_secrets_injection")
    end
  end

  describe "subsequent boot — no env-provided password" do
    let!(:admin) do
      User.create!(email: email, password: "Initial-Pwd-1234",
                   password_confirmation: "Initial-Pwd-1234",
                   admin: true, status: "active", display_name: "Admin")
    end

    it "is a no-op on the password" do
      original_digest = admin.password_digest
      task.invoke
      expect(admin.reload.password_digest).to eq(original_digest)
    end

    it "fixes the admin flag if it has been cleared" do
      admin.update!(admin: false)
      task.invoke
      expect(admin.reload.admin?).to eq(true)
    end
  end

  describe "subsequent boot — rotation detected" do
    let!(:admin) do
      User.create!(email: email, password: "Initial-Pwd-1234",
                   password_confirmation: "Initial-Pwd-1234",
                   admin: true, status: "active", display_name: "Admin")
    end

    before { ENV["SPARC_ADMIN_PASSWORD"] = "Rotated-Pwd-5678" }

    it "syncs the DB password to match the env value" do
      task.invoke
      expect(admin.reload.authenticate("Rotated-Pwd-5678")).to be_truthy
      expect(admin.authenticate("Initial-Pwd-1234")).to be_falsey
    end

    it "marks must_reset_password and bumps password_changed_at" do
      admin.update!(must_reset_password: false, password_changed_at: 30.days.ago)
      task.invoke
      admin.reload
      expect(admin.must_reset_password).to eq(true)
      expect(admin.password_changed_at).to be_within(5.seconds).of(Time.current)
    end

    it "writes a sync audit event" do
      expect {
        task.invoke
      }.to change { AuditEvent.where(action: "admin_credential_synced_from_env").count }.by(1)
      event = AuditEvent.where(action: "admin_credential_synced_from_env").last
      expect(event.metadata["source"]).to eq("ecs_secrets_injection")
    end

    it "is idempotent when env matches DB" do
      admin.update!(password: "Rotated-Pwd-5678", password_confirmation: "Rotated-Pwd-5678")
      digest_before = admin.reload.password_digest
      expect {
        task.invoke
      }.not_to change { AuditEvent.where(action: "admin_credential_synced_from_env").count }
      expect(admin.reload.password_digest).to eq(digest_before)
    end
  end

  describe "local login disabled" do
    it "skips entirely" do
      allow(SparcConfig).to receive(:enable_local_login?).and_return(false)
      expect { task.invoke }.not_to change { User.count }
    end
  end
end
