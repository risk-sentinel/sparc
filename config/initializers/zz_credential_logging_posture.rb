# frozen_string_literal: true

# #834 — announce, loudly, when credential redaction has been switched OFF.
#
# `SPARC_LOG_CREDENTIALS=true` exists for a real need: when the thing
# being debugged IS the credential ("is the app receiving the rotated
# password?"), `[REDACTED]` answers nothing. But the consequence outlives the
# troubleshooting session — anything logged while it is on stays in the log
# aggregator for the life of the log group, where far more people can read it
# than can read the secret itself.
#
# So the operator who turned it on gets told what it costs, and is told to treat
# the exposed password as compromised. With #834 that remediation is cheap: a
# Secrets Manager rotation plus a task restart, no redeploy and no IaC change.
#
# Warns, never raises — a diagnostic must not be the reason a deploy fails.
#
# NIST 800-53: AU-9 (Protection of Audit Information), IA-5(1) (Authenticator
# Management), SI-11 (Error Handling).
Rails.application.config.after_initialize do
  next unless ENV.fetch("SPARC_LOG_CREDENTIALS", "false") == "true"
  # assets:precompile boots the app just to build assets; nothing is logged
  # there worth warning about.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  Rails.logger.warn(
    "[SPARC] ⚠️  CREDENTIAL REDACTION IS DISABLED (SPARC_LOG_CREDENTIALS=true). " \
    "Database passwords and connection strings will be written to the logs IN CLEAR TEXT, " \
    "including anything an exception message carries. Use this only for as long as the " \
    "credential itself is what you are debugging, then unset it — and treat every password " \
    "logged while it was on as COMPROMISED and rotate it. Rotation is a Secrets Manager " \
    "change plus a task restart; no redeploy is required."
  )
end
