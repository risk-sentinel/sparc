# frozen_string_literal: true

# #587 — classify a local-login failure into one of a small fixed
# enum of operator-friendly reason codes, suitable for inclusion in
# `audit_event.metadata[:reason]`. The user-facing flash message
# stays generic ("Invalid email or password"); only the audit log —
# which only admins see — carries the specific reason.
#
# Usage:
#
#   reason = LoginFailureReason.classify(user: user, password: password)
#   AuditEvent.log(action: "login_failure", metadata: { reason: reason, ... })
#
# Reason codes (stable strings — safe for grouping / alerting):
#
#   unknown_email      — no user record matches the submitted email
#   no_local_password  — user exists, password_digest IS NULL (OAuth-only)
#   suspended          — user.status == "suspended" (admin-disabled
#                        or auto-deactivated via SuspensionService)
#   invalid_password   — user exists, password_digest present, but
#                        authenticate(password) returns false
#   other              — escape hatch for any unanticipated path
#
# `service_account_web_login` and `account_deactivated` are recorded
# at their dedicated short-circuit branches in
# SessionsController#authenticate_local before this classifier runs;
# they remain in the audit log as their own distinct strings and are
# not re-classified here.
module LoginFailureReason
  REASONS = %w[
    unknown_email
    no_local_password
    suspended
    invalid_password
    other
  ].freeze

  extend self

  def classify(user:, password:)
    return "unknown_email"     if user.nil?
    return "no_local_password" if user.password_digest.blank?
    return "suspended"         if user.status == "suspended"
    return "invalid_password"  unless user.authenticate(password.to_s)

    "other"
  end
end
