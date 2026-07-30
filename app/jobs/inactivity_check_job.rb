# frozen_string_literal: true

# Background job that auto-deactivates users who haven't signed in within
# the configured inactivity threshold (SPARC_INACTIVITY_DAYS, default 30).
#
# Idempotent — only affects active users past the threshold.
# System action — audit events are logged with user: nil.
#
# Trigger via cron:
#   rails runner "InactivityCheckJob.perform_now"
#
# Or schedule with sidekiq-cron / solid_queue recurring.
#
# NIST 800-53 Controls:
#   AC-2(3) Disable Accounts (automatic deactivation past SPARC_INACTIVITY_DAYS)
#   AC-2(4) Automated Audit Actions (system-actor AuditEvent per deactivation)
# The break-glass admin (SparcConfig.admin_email) and the last active admin are
# exempt (#878). AC-2(3) mandates disabling inactive accounts, but disabling the
# only administrator would deny administration entirely with no self-service
# recovery — the exemption keeps AC-2(3) from defeating AC-2 itself. The scope
# (User.inactive_past_threshold) carries the exemption, not this job.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class InactivityCheckJob < ApplicationJob
  queue_as :default

  def perform
    threshold = SparcConfig.inactivity_days
    users = User.inactive_past_threshold(threshold)

    users.find_each do |user|
      # #878 — one protected account must not abort the sweep for everyone
      # else. The break-glass admin is already excluded by the scope; this
      # catches the last-admin case, which the scope cannot express.
      begin
        user.deactivate!(reason: "auto_inactivity")
      rescue User::LastAdminError => e
        Rails.logger.warn("[InactivityCheck] Skipped #{user.email}: #{e.message}")
        next
      end

      AuditEvent.log(
        user: nil,
        action: "user_auto_deactivated",
        subject: user,
        metadata: {
          target_user_id: user.id,
          target_email: user.email,
          uuid: user.uuid,
          inactivity_days: threshold,
          last_sign_in_at: user.last_sign_in_at&.iso8601
        }
      )

      Rails.logger.info("[InactivityCheck] Deactivated user #{user.email} (UUID: #{user.uuid}) — inactive for #{threshold}+ days")
    end

    Rails.logger.info("[InactivityCheck] Complete — #{users.count} user(s) deactivated")
  end
end
