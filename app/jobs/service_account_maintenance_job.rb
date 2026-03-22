# frozen_string_literal: true

# Daily maintenance job for service account lifecycle management.
#
# Checks two conditions and auto-disables service accounts:
# 1. Token expiry — all tokens have expired (no active tokens remaining)
# 2. Inactivity — no API call within SPARC_SA_INACTIVITY_DAYS (default 90)
#
# Runs via Solid Queue recurring schedule (config/recurring.yml).
# Disabled accounts can be re-enabled by an admin via the Service Accounts UI.
#
# NIST 800-53 Controls:
#   AC-2(1) Automated Account Management (daily auto-disable)
#   AC-2(3) Disable Inactive Accounts (configurable threshold)
#   AU-2    Event Logging (audit events for each auto-disable)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class ServiceAccountMaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    expired_count = disable_expired_token_accounts
    inactive_count = disable_inactive_accounts

    Rails.logger.info("[ServiceAccountMaintenance] " \
      "Disabled #{expired_count} expired, #{inactive_count} inactive")
  end

  private

  # Disable service accounts where ALL tokens have expired.
  # Accounts with no tokens or at least one non-expired token are skipped.
  def disable_expired_token_accounts
    count = 0
    User.where(service_account: true, status: "active").find_each do |sa|
      next if sa.api_tokens.empty?
      next if sa.api_tokens.where("expires_at IS NULL OR expires_at > ?", Time.current).exists?

      sa.disable!(reason: "token_expired")
      AuditEvent.log(
        user: nil,
        action: "service_account_auto_disabled",
        subject: sa,
        metadata: {
          reason: "token_expired",
          email: sa.email,
          last_token_expired_at: sa.api_tokens.maximum(:expires_at)&.iso8601
        }
      )
      count += 1
    end
    count
  end

  # Disable service accounts that have not been used within the inactivity threshold.
  # Uses max(api_tokens.last_used_at) as the activity baseline; falls back to created_at
  # for accounts that have never been used.
  def disable_inactive_accounts
    threshold = SparcConfig.sa_inactivity_days
    cutoff = threshold.days.ago
    count = 0

    User.where(service_account: true, status: "active").find_each do |sa|
      last_used = sa.api_tokens.maximum(:last_used_at)
      baseline = last_used || sa.created_at
      next if baseline > cutoff

      sa.disable!(reason: "inactivity")
      AuditEvent.log(
        user: nil,
        action: "service_account_auto_disabled",
        subject: sa,
        metadata: {
          reason: "inactivity",
          email: sa.email,
          inactivity_days: threshold,
          last_used_at: last_used&.iso8601
        }
      )
      count += 1
    end
    count
  end
end
