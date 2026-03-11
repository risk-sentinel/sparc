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
class InactivityCheckJob < ApplicationJob
  queue_as :default

  def perform
    threshold = SparcConfig.inactivity_days
    users = User.inactive_past_threshold(threshold)

    users.find_each do |user|
      user.deactivate!(reason: "auto_inactivity")

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
