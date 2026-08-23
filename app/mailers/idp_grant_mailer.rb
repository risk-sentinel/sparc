# frozen_string_literal: true

# #860 — tell the administrators that the directory is asking for access SPARC
# cannot grant.
#
# An unmatched grant is silent by nature: the user signs in successfully, with
# less access than their directory says they should have, and nothing about the
# login looks wrong. Without this the first signal is a support ticket from
# someone who cannot see their own boundary.
#
# NIST 800-53: AC-2(1) Automated Account Management, AU-6 Audit Review.
class IdpGrantMailer < ApplicationMailer
  # `summary` is [{ reason:, occurrences:, affected_users:, example_grant: }],
  # already grouped — the same shape the API's meta.summary returns, so the
  # digest and the queue cannot disagree about what is outstanding.
  def unmatched_grants_digest(summary:, window_hours:)
    @summary = summary
    @window_hours = window_hours
    @total_users = summary.sum { |row| row[:affected_users] }

    recipients = admin_emails
    return message.perform_deliveries = false if recipients.empty?

    mail(
      to: recipients,
      subject: "[#{SparcConfig.app_name}] #{@summary.size} IdP grant " \
               "#{'issue'.pluralize(@summary.size)} affecting #{@total_users} " \
               "#{'user'.pluralize(@total_users)}"
    )
  end

  private

  def admin_emails
    User.where(admin: true, service_account: false, status: "active").pluck(:email)
  end
end
