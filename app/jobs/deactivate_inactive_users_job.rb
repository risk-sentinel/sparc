# frozen_string_literal: true

# #860 — deactivate accounts that have stopped being used.
#
# This is SPARC's offboarding mechanism, and it is deliberately indirect. SPARC
# is never told that an IdP disabled someone: entitlements are resolved at login
# (owner-decided), and a disabled account simply stops logging in. Absence of
# sign-in is therefore the one signal that covers every case at once — a leaver,
# a revoked IdP account, a dormant local login — without SPARC needing a second
# authenticated inbound channel from the directory.
#
# Disabled by default. `SPARC_USER_INACTIVITY_DAYS` must be set, so an upgrade
# never begins deactivating people on its own.
#
# NIST 800-53: AC-2(3) Disable Accounts.
class DeactivateInactiveUsersJob < ApplicationJob
  queue_as :background

  def perform
    days = SparcConfig.user_inactivity_days
    return if days <= 0

    cutoff = days.days.ago
    deactivated = 0
    skipped = []

    inactive_scope(cutoff).find_each do |user|
      begin
        user.deactivate!(reason: "inactivity")
      rescue User::LastAdminError => e
        # The instance must stay administrable. User#deactivate! raises rather
        # than letting an unattended job strand the estate — the exact scenario
        # its own comment names. Recorded, not swallowed: an administrator idle
        # past the threshold is worth someone knowing about.
        skipped << { email: user.email, reason: e.message }
        next
      end

      deactivated += 1
      AuditEvent.log(user: user, action: "user_deactivated_for_inactivity",
                     metadata: { inactivity_days: days,
                                 last_seen_at: last_seen(user)&.iso8601 })
    end

    Rails.logger.info(
      "[DeactivateInactiveUsersJob] threshold=#{days}d deactivated=#{deactivated} skipped=#{skipped.size}"
    )
    skipped.each { |s| Rails.logger.warn("[DeactivateInactiveUsersJob] skipped #{s[:email]}: #{s[:reason]}") }

    { deactivated: deactivated, skipped: skipped }
  end

  private

  # A user who has NEVER signed in is measured from when their account was
  # created. Otherwise an account provisioned and then abandoned would sit
  # active forever, which is the same stale-account risk the control addresses.
  #
  # Service accounts are excluded: they authenticate with tokens and never set
  # last_sign_in_at, so including them would deactivate every one of them on the
  # first run. Their own lifecycle is ServiceAccountMaintenanceJob.
  def inactive_scope(cutoff)
    User.where(status: "active")
        .where(service_account: false)
        .where("COALESCE(users.last_sign_in_at, users.created_at) < ?", cutoff)
  end

  def last_seen(user) = user.last_sign_in_at || user.created_at
end
