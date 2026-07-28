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

    # #841 — a Secrets-Manager-managed credential must NOT be forced to change.
    #
    # Forcing it produced a loop: the operator changes the password, the value
    # recorded in Secrets Manager is now stale, and on the next restart the
    # reconciliation branch sees the mismatch and overwrites their choice —
    # forcing another change, forever. A break-glass account whose stored
    # password does not work is worse than none, because it fails exactly when
    # it is needed.
    it "does NOT force a reset when the password came from Secrets Manager" do
      ENV["SPARC_ADMIN_PASSWORD"] = "Injected-From-SM-1234"

      task.invoke

      admin = User.find_by(email: email)
      expect(admin.must_reset_password).to eq(false),
        "forcing a change on an SM-managed credential guarantees the two diverge"
      expect(admin.password_changed_at).to be_present
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

    # #841 — this example used to assert `must_reset_password == true`, which
    # encoded the defect rather than a requirement. Forcing a change on a value
    # that CAME FROM Secrets Manager guarantees the stored credential goes
    # stale the moment the operator complies, and the next restart then
    # overwrites their new password and forces another change. The contract is
    # now the opposite: a synced credential is immediately usable.
    it "bumps password_changed_at WITHOUT forcing a change" do
      admin.update!(must_reset_password: false, password_changed_at: 30.days.ago)
      task.invoke
      admin.reload
      expect(admin.must_reset_password).to eq(false),
        "the password came from Secrets Manager — forcing a change re-creates the drift loop"
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

  # The regression that motivated #841: rotate in Secrets Manager, restart, and
  # the new value must take effect WITHOUT stranding the operator in a forced
  # change — and without a second restart undoing anything.
  describe "rotation propagation (#841)" do
    it "syncs a rotated password and leaves the account usable" do
      ENV["SPARC_ADMIN_PASSWORD"] = "Original-From-SM-1234"
      task.invoke
      task.reenable

      ENV["SPARC_ADMIN_PASSWORD"] = "Rotated-In-SM-5678"
      task.invoke

      admin = User.find_by(email: email)
      expect(admin.authenticate("Rotated-In-SM-5678")).to be_truthy
      expect(admin.authenticate("Original-From-SM-1234")).to be_falsey
      expect(admin.must_reset_password).to eq(false),
        "a rotated SM credential must be usable immediately — forcing a change " \
        "here is what made the stored credential stale in the first place"
    end

    # Restarting with an UNCHANGED secret must be a no-op. If it re-forced a
    # reset, every deploy would strand the break-glass account.
    it "is idempotent across restarts with the same secret" do
      ENV["SPARC_ADMIN_PASSWORD"] = "Stable-From-SM-1234"
      task.invoke
      task.reenable
      task.invoke

      admin = User.find_by(email: email)
      expect(admin.authenticate("Stable-From-SM-1234")).to be_truthy
      expect(admin.must_reset_password).to eq(false)
    end
  end
end
