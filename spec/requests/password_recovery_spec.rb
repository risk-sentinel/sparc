# frozen_string_literal: true

require "rails_helper"

# #841 — a forgotten local-login password used to be unrecoverable. An admin
# could not set one (`user_params` permitted only name fields), no self-service
# flow existed, and the one password screen requires the CURRENT password —
# which is exactly what has been lost. The only way back in was a Rails console.
#
# Two recovery routes, because deployments differ. Both are covered here, and
# so is the property that makes them safe: the admin never ends up knowing a
# password the user keeps.
RSpec.describe "Password recovery (#841)", type: :request do
  # Test fixtures, not credentials. Named once so the scanner allow-list marks a
  # single declaration instead of every call site, and so the intent is obvious
  # to a human reader too.
  CHOSEN_PASSWORD = "BrandNewPassword1"        # gitleaks:allow
  SECOND_ATTEMPT  = "SecondAttempt12345"       # gitleaks:allow
  PRIOR_PASSWORD  = "OldKnownPassword1"        # gitleaks:allow
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user, email: "locked.out@example.gov") }

  before do
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    sign_in_as(admin)
  end

  # ── Flow B: temporary password, handed over out of band ──────────────────
  describe "PATCH /admin/users/:id/reset_password" do
    it "issues a temporary password the user must change at first sign-in" do
      patch reset_password_admin_user_path(user)

      temporary = flash[:temporary_password]
      expect(temporary).to be_present, "the admin has nothing to hand over"

      user.reload
      expect(user.authenticate(temporary)).to be_truthy
      expect(user.must_reset_password).to be(true),
        "the admin necessarily saw this credential, so it must not survive the first login"
    end

    it "invalidates the previous password immediately" do
      user.update!(password: PRIOR_PASSWORD, password_confirmation: PRIOR_PASSWORD)

      patch reset_password_admin_user_path(user)

      expect(user.reload.authenticate(PRIOR_PASSWORD)).to be_falsey
    end

    it "audits the issuance, naming the target" do
      expect { patch reset_password_admin_user_path(user) }
        .to change { AuditEvent.where(action: "admin_temporary_password_issued").count }.by(1)
    end

    it "refuses to hand a working credential to a suspended account" do
      user.update!(status: "suspended")

      patch reset_password_admin_user_path(user)

      expect(flash[:temporary_password]).to be_blank
      expect(flash[:error]).to match(/active user/i)
    end

    it "is admin-only" do
      sign_in_as(create(:user))

      patch reset_password_admin_user_path(user)

      expect(response).not_to have_http_status(:ok)
      expect(flash[:temporary_password]).to be_blank
    end
  end

  # ── Flow A: emailed one-time link ────────────────────────────────────────
  describe "PATCH /admin/users/:id/email_password_reset" do
    it "sends a link and stores only its digest" do
      allow(SparcConfig).to receive(:enable_smtp?).and_return(true)

      expect { patch email_password_reset_admin_user_path(user) }
        .to have_enqueued_mail(PasswordResetMailer, :reset_link)

      user.reload
      expect(user.password_reset_digest).to be_present
      expect(user.password_reset_expires_at).to be_future
    end

    # Without mail the link goes nowhere, so say so rather than reporting
    # success for an email nobody will receive.
    it "refuses when the instance has no mail configured" do
      allow(SparcConfig).to receive(:enable_smtp?).and_return(false)

      expect { patch email_password_reset_admin_user_path(user) }
        .not_to have_enqueued_mail(PasswordResetMailer, :reset_link)

      expect(flash[:error]).to match(/no mail configured/i)
    end
  end

  # ── Redeeming an emailed link ────────────────────────────────────────────
  describe "the reset link itself" do
    let!(:token) { user.issue_password_reset! }

    it "lets the user set a password WITHOUT knowing the old one" do
      # The whole point: PasswordsController#update demands the current
      # password, which is the thing that has been lost.
      patch password_reset_path(token: token),
            params: { new_password: CHOSEN_PASSWORD, new_password_confirmation: CHOSEN_PASSWORD }

      user.reload
      expect(user.authenticate(CHOSEN_PASSWORD)).to be_truthy
      expect(user.must_reset_password).to be(false),
        "the user chose this one themselves, so forcing another change would strand them"
    end

    it "works only once" do
      patch password_reset_path(token: token),
            params: { new_password: CHOSEN_PASSWORD, new_password_confirmation: CHOSEN_PASSWORD }

      patch password_reset_path(token: token),
            params: { new_password: SECOND_ATTEMPT, new_password_confirmation: SECOND_ATTEMPT }

      expect(user.reload.authenticate(SECOND_ATTEMPT)).to be_falsey
    end

    it "rejects an expired token" do
      user.update!(password_reset_expires_at: 1.minute.ago)

      patch password_reset_path(token: token),
            params: { new_password: CHOSEN_PASSWORD, new_password_confirmation: CHOSEN_PASSWORD }

      expect(user.reload.authenticate(CHOSEN_PASSWORD)).to be_falsey
    end

    it "rejects a forged token" do
      get edit_password_reset_path(token: "not-a-real-token")

      expect(response).to redirect_to(login_path)
    end

    # Issuing a temporary password must not leave a live link behind — two ways
    # into one account is one more than anyone intended.
    it "is invalidated when a temporary password is issued afterwards" do
      user.issue_temporary_password!

      patch password_reset_path(token: token),
            params: { new_password: CHOSEN_PASSWORD, new_password_confirmation: CHOSEN_PASSWORD }

      expect(user.reload.authenticate(CHOSEN_PASSWORD)).to be_falsey
    end
  end
end
