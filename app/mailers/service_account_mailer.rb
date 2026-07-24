# frozen_string_literal: true

# Sends email notifications for service account token lifecycle events.
#
# NIST 800-53 Controls:
#   AC-2(1) Automated Account Management — proactive notifications before auto-disable
#   AC-2(3) Disable Inactive Accounts — inactivity warnings before threshold
class ServiceAccountMailer < ApplicationMailer
  # Sent to the service account owner 14 days before token expiry.
  def token_expiry_warning(service_account, days_remaining:)
    return unless SparcConfig.enable_smtp?

    @service_account = service_account
    @days_remaining = days_remaining
    @owner = service_account.owner
    @admin_url = admin_service_accounts_url(host: SparcConfig.app_host)

    mail(
      to: @owner&.email,
      subject: "[SPARC] Service account '#{service_account.first_name}' token expires in #{days_remaining} days"
    )
  end

  # Sent to owner + all instance admins 7 days before token expiry.
  def token_expiry_urgent(service_account, days_remaining:)
    return unless SparcConfig.enable_smtp?

    @service_account = service_account
    @days_remaining = days_remaining
    @owner = service_account.owner
    @admin_url = admin_service_accounts_url(host: SparcConfig.app_host)

    recipients = [ @owner&.email, *admin_emails ].compact.uniq
    mail(
      to: recipients,
      subject: "[SPARC] URGENT: Service account '#{service_account.first_name}' token expires in #{days_remaining} days"
    )
  end

  # Sent to owner + all instance admins when the account is auto-disabled due to token expiry.
  def token_expired_notice(service_account)
    return unless SparcConfig.enable_smtp?

    @service_account = service_account
    @owner = service_account.owner
    @admin_url = admin_service_accounts_url(host: SparcConfig.app_host)

    recipients = [ @owner&.email, *admin_emails ].compact.uniq
    mail(
      to: recipients,
      subject: "[SPARC] Service account '#{service_account.first_name}' disabled — token expired"
    )
  end

  # Sent to owner when the service account approaches the inactivity threshold.
  def inactivity_warning(service_account, inactive_days:)
    return unless SparcConfig.enable_smtp?

    @service_account = service_account
    @inactive_days = inactive_days
    @threshold = SparcConfig.inactivity_days  # #785 Pass 2.1 — unified inactivity window
    @owner = service_account.owner
    @admin_url = admin_service_accounts_url(host: SparcConfig.app_host)

    mail(
      to: @owner&.email,
      subject: "[SPARC] Service account '#{service_account.first_name}' inactive for #{inactive_days} days"
    )
  end

  private

  def admin_emails
    User.where(admin: true, service_account: false).pluck(:email)
  end
end
