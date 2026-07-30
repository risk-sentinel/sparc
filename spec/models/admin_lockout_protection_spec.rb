# frozen_string_literal: true

require "rails_helper"

# #878 — two ways SPARC could lock an operator out of their own instance.
#
# `SessionsController#authenticate_local` gates on `user&.active?`, so
# deactivation is a HARD stop — unlike password expiry, which still
# authenticates and merely forces a change. Reactivation needs another admin,
# so the only recovery from an empty admin set is shell access and a rake task.
#
#   1. InactivityCheckJob auto-deactivating the break-glass admin for idleness.
#      Currently dormant (the job is not in config/recurring.yml), but
#      docs/ENVIRONMENT_VARIABLES.md tells operators to schedule it.
#   2. Deactivating or suspending the last active admin, by any path.
RSpec.describe "Admin lockout protection (#878)" do
  let(:admin_email) { "breakglass@example.gov" }

  before { allow(SparcConfig).to receive(:admin_email).and_return(admin_email) }

  describe "the break-glass account is exempt from inactivity" do
    it "is not swept up when idle past the threshold" do
      break_glass = create(:user, email: admin_email, admin: true,
                           last_sign_in_at: 90.days.ago)

      expect(User.inactive_past_threshold(30)).not_to include(break_glass)
    end

    it "matches the configured email case-insensitively" do
      # An email differing only in case must not slip past the exemption —
      # that is the exact outcome it exists to prevent.
      break_glass = create(:user, email: admin_email.upcase, admin: true,
                           last_sign_in_at: 90.days.ago)

      expect(User.inactive_past_threshold(30)).not_to include(break_glass)
    end

    it "still sweeps a NAMED admin — the exemption is the account, not the bit" do
      named_admin = create(:user, email: "alice@example.gov", admin: true,
                           last_sign_in_at: 90.days.ago)

      expect(User.inactive_past_threshold(30)).to include(named_admin)
    end

    it "still sweeps ordinary idle users" do
      ordinary = create(:user, email: "bob@example.gov", last_sign_in_at: 90.days.ago)

      expect(User.inactive_past_threshold(30)).to include(ordinary)
    end

    it "leaves recently active users alone" do
      recent = create(:user, email: "carol@example.gov", last_sign_in_at: 1.day.ago)

      expect(User.inactive_past_threshold(30)).not_to include(recent)
    end
  end

  describe "the break-glass account is exempt from password expiry" do
    it "never expires — its credential is rotated out of band" do
      break_glass = create(:user, email: admin_email, admin: true,
                           password_changed_at: 400.days.ago)

      expect(break_glass.password_expired?).to be(false)
    end

    it "still expires a NAMED admin's password" do
      named_admin = create(:user, email: "alice@example.gov", admin: true,
                           password_changed_at: 400.days.ago)

      expect(named_admin.password_expired?).to be(true)
    end
  end

  describe "the last active admin cannot be removed" do
    it "refuses deactivation and says why" do
      only_admin = create(:user, email: "solo@example.gov", admin: true, status: "active")

      expect { only_admin.deactivate! }.to raise_error(User::LastAdminError, /only active administrator/)
      expect(only_admin.reload).to be_active
    end

    it "refuses suspension too — suspended accounts cannot authenticate either" do
      only_admin = create(:user, email: "solo@example.gov", admin: true, status: "active")

      expect { only_admin.update!(status: "suspended") }
        .to raise_error(ActiveRecord::RecordInvalid, /only active administrator/)
      expect(only_admin.reload).to be_active
    end

    it "allows it once another active admin exists" do
      first  = create(:user, email: "first@example.gov", admin: true, status: "active")
      create(:user, email: "second@example.gov", admin: true, status: "active")

      expect { first.deactivate! }.not_to raise_error
      expect(first.reload).to be_deactivated
    end

    it "does not count an INACTIVE admin as cover" do
      only_active = create(:user, email: "active@example.gov", admin: true, status: "active")
      create(:user, email: "dormant@example.gov", admin: true, status: "deactivated")

      expect { only_active.deactivate! }.to raise_error(User::LastAdminError)
    end

    it "does not block a non-admin" do
      create(:user, email: "solo-admin@example.gov", admin: true, status: "active")
      ordinary = create(:user, email: "user@example.gov", status: "active")

      expect { ordinary.deactivate! }.not_to raise_error
    end

    it "does not block re-saving an already inactive admin" do
      create(:user, email: "other@example.gov", admin: true, status: "active")
      dormant = create(:user, email: "dormant@example.gov", admin: true, status: "deactivated")

      expect { dormant.update!(inactive_reason: "tidied") }.not_to raise_error
    end
  end

  describe "the refusal reaches the audit trail" do
    # AuditEvent::ACTIONS is an allowlist and audit_log fails SILENTLY for an
    # unlisted action (see the #567 note in spec/requests/api/v1/users_spec.rb).
    # A refusal nobody can see afterwards is barely a refusal.
    it "allowlists both refusal actions" do
      expect(AuditEvent::ACTIONS).to include("user_deactivate_refused", "user_suspend_refused")
    end

    # The controller-level assertion — that the refusal is actually written and
    # surfaced to the admin — lives in spec/requests/admin/users_spec.rb, where
    # the request infrastructure belongs.
  end

  describe "InactivityCheckJob" do
    it "skips a protected account without aborting the sweep for everyone else" do
      create(:user, email: "solo@example.gov", admin: true, status: "active",
             last_sign_in_at: 90.days.ago)
      ordinary = create(:user, email: "idle@example.gov", status: "active",
                        last_sign_in_at: 90.days.ago)

      expect { InactivityCheckJob.perform_now }.not_to raise_error

      expect(ordinary.reload).to be_deactivated
    end

    it "leaves the break-glass admin active even when the job runs" do
      break_glass = create(:user, email: admin_email, admin: true, status: "active",
                           last_sign_in_at: 90.days.ago)
      create(:user, email: "other-admin@example.gov", admin: true, status: "active")

      InactivityCheckJob.perform_now

      expect(break_glass.reload).to be_active
    end
  end
end
