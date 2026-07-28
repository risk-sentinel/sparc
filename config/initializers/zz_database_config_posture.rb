# frozen_string_literal: true

# #834 — say which database configuration actually took effect.
#
# There are three ways to configure the connection and a strict precedence
# between them (DB_CREDENTIALS > DATABASE_URL > SPARC_DB_*), but that precedence
# is INVISIBLE at runtime. An operator who sets SPARC_DB_HOST alongside
# DB_CREDENTIALS gets the credentials one and nothing tells them their variable
# was ignored; they then debug a host they are not connected to. The removal of
# DATABASE_URL makes it worse, because afterwards nothing can even tell it was
# set.
#
# Two hazards are reported, both of which are silent otherwise:
#
#   * a source that is CONFIGURED BUT LOSES, so an operator can see that the
#     variable they are editing is not the one in use;
#   * a PARTIAL SPARC_DB_* block. That block has no all-or-nothing guard of its
#     own (unlike DB_CREDENTIALS), so a missing SPARC_DB_PASSWORD does not fail
#     — it connects with no password, and the error surfaces as a permission
#     problem somewhere else entirely.
#
# Reports the source at INFO even when everything is clean: "which of these is
# in effect?" should be answerable from the logs rather than by reading
# lib/db_url/config.rb.
#
# Warns, never raises, and never echoes a value — a diagnostic must not be the
# reason a deploy fails, and this one is about credentials.
#
# NIST 800-53: CM-6 (Configuration Settings), SI-11 (Error Handling).
Rails.application.config.after_initialize do
  # assets:precompile boots in production purely to build assets, with no
  # database configured; the warning would be noise.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?
  next unless Rails.env.production?

  begin
    source = DbUrl.source
    Rails.logger.info("[SPARC] Database configuration source: #{source}.")

    if source == :defaults
      Rails.logger.warn(
        "[SPARC] ⚠️  No database configuration found (DB_CREDENTIALS, DATABASE_URL and " \
        "SPARC_DB_* are all unset). Falling back to built-in defaults, which are for local " \
        "development and will not reach a managed database."
      )
    end

    overridden = DbUrl.overridden_sources
    if overridden.any?
      Rails.logger.warn(
        "[SPARC] ⚠️  More than one database configuration is set. #{source} is in effect; " \
        "#{overridden.join(' and ')} #{overridden.one? ? 'is' : 'are'} present but IGNORED. " \
        "Editing the ignored one will have no effect. Precedence is " \
        "DB_CREDENTIALS > DATABASE_URL > SPARC_DB_* — see docs/ENVIRONMENT_VARIABLES.md."
      )
    end

    missing = DbUrl.sparc_db_vars_missing
    if missing.any? && source == :sparc_db_vars
      Rails.logger.warn(
        "[SPARC] ⚠️  The SPARC_DB_* block is incomplete: #{missing.join(', ')} " \
        "#{missing.one? ? 'is' : 'are'} unset and will take a built-in default, so SPARC may " \
        "be connecting somewhere other than intended. Set every member, or use DB_CREDENTIALS, " \
        "which is validated all-or-nothing. (A missing SPARC_DB_PASSWORD is handled more " \
        "strictly and refuses to boot outright — #849.)"
      )
    end

    # #849 — reaching here at all means a password WAS resolved, since a blank
    # one raises during database.yml render, long before initializers run. The
    # exception is a deployment that opted out explicitly, which is legitimate
    # (RDS IAM auth) but must not be invisible: it is the one path on which
    # SPARC connects with no credential, so it says so on every boot.
    if DbUrl.resolved_password.nil? && DbUrl.allow_empty_password?
      Rails.logger.warn(
        "[SPARC] ⚠️  Connecting with NO database password: #{DbUrl::ALLOW_EMPTY_PASSWORD_VAR} " \
        "is set, which disables the check that would otherwise refuse to start. This is " \
        "correct only when the database authenticates by another means, such as RDS IAM " \
        "authentication. Unset it if that is not the case."
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[SPARC] Database configuration posture check skipped: #{e.class}: #{e.message}")
  end
end
