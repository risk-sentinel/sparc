# frozen_string_literal: true

# Daily job that sends email notifications for service account token lifecycle events.
# Runs 30 minutes before ServiceAccountMaintenanceJob to give owners advance warning.
#
# Notifications:
#   - 14 days before token expiry: warning to owner
#   - 7 days before token expiry: urgent to owner + admins
#   - On auto-disable (token expired): notice to owner + admins
#   - Approaching inactivity threshold: warning to owner
#
# NIST 800-53 Controls:
#   AC-2(1) Automated Account Management — proactive notifications
#   AC-2(3) Disable Inactive Accounts — inactivity warnings
class ServiceAccountNotificationJob < ApplicationJob
  queue_as :default

  def perform
    return unless SparcConfig.enable_smtp?

    warning_count = send_expiry_warnings
    urgent_count = send_expiry_urgent
    expired_count = send_expired_notices
    inactivity_count = send_inactivity_warnings

    Rails.logger.info(
      "[ServiceAccountNotifications] Sent #{warning_count} warnings, " \
      "#{urgent_count} urgent, #{expired_count} expired, #{inactivity_count} inactivity"
    )
  end

  private

  # Service accounts with soonest-expiring token between 8-14 days out.
  # (7 and under handled by urgent)
  def send_expiry_warnings
    count = 0
    active_service_accounts.find_each do |sa|
      soonest = soonest_expiring_token(sa)
      next unless soonest
      days = days_until(soonest.expires_at)
      next unless days.between?(8, 14)

      ServiceAccountMailer.token_expiry_warning(sa, days_remaining: days).deliver_later
      count += 1
    end
    count
  end

  # Service accounts with soonest-expiring token within 7 days.
  def send_expiry_urgent
    count = 0
    active_service_accounts.find_each do |sa|
      soonest = soonest_expiring_token(sa)
      next unless soonest
      days = days_until(soonest.expires_at)
      next unless days.between?(1, 7)

      ServiceAccountMailer.token_expiry_urgent(sa, days_remaining: days).deliver_later
      count += 1
    end
    count
  end

  # Service accounts auto-disabled today due to token expiry.
  def send_expired_notices
    count = 0
    User.where(service_account: true, disabled_reason: "token_expired")
        .where(disabled_at: Time.current.beginning_of_day..Time.current.end_of_day)
        .find_each do |sa|
      ServiceAccountMailer.token_expired_notice(sa).deliver_later
      count += 1
    end
    count
  end

  # Active service accounts approaching inactivity threshold (within 7 days).
  def send_inactivity_warnings
    threshold = SparcConfig.sa_inactivity_days
    warning_start = (threshold - 7).days.ago
    count = 0

    active_service_accounts.find_each do |sa|
      last_used = sa.api_tokens.maximum(:last_used_at)
      baseline = last_used || sa.created_at
      inactive_days = ((Time.current - baseline) / 1.day).to_i
      next unless inactive_days >= (threshold - 7) && inactive_days < threshold

      ServiceAccountMailer.inactivity_warning(sa, inactive_days: inactive_days).deliver_later
      count += 1
    end
    count
  end

  def active_service_accounts
    User.where(service_account: true, status: "active")
  end

  def soonest_expiring_token(service_account)
    service_account.api_tokens
                   .where.not(expires_at: nil)
                   .where("expires_at > ?", Time.current)
                   .order(:expires_at)
                   .first
  end

  def days_until(time)
    ((time - Time.current) / 1.day).ceil
  end
end
