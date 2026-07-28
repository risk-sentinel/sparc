# frozen_string_literal: true

require "json"

# #785 Pass 2 — collapse the six SPARC_DB_* variables into DATABASE_URL.
#
# The problem this solves: Rails merges DATABASE_URL into the `primary` database
# ONLY (activerecord database_configurations.rb: `url ||= ENV["DATABASE_URL"] if
# name == "primary"`). The cache/queue/cable secondaries inherit the YAML anchor,
# not the merge, so a task definition that dropped SPARC_DB_* and kept only
# DATABASE_URL would silently repoint those three at localhost with no password.
#
# So config/database.yml derives every database's connection from these methods,
# each of which prefers DATABASE_URL and falls back to SPARC_DB_* when it is
# unset. SPARC_DB_* stays a fully supported fallback — this reduces what must be
# SET, not what works.
#
# Parsing uses Rails' OWN ConnectionUrlResolver, the exact class that resolves
# DATABASE_URL for `primary`, so the secondaries decode identically — same
# percent-decoding of passwords, same defaults. Hand-rolled URI parsing would
# risk the secondaries disagreeing with primary on a password with special
# characters.
#
# database.yml must stay parseable as raw YAML (editors and tooling read it
# without rendering ERB — a broken database.yml shipped undetected once, #788).
# That rules out a `<% ... %>` statement block in the file, so ALL logic lives
# here and database.yml uses only inline `<%= DbUrl.something %>` expressions.
# This file is required from config/application.rb before the app class is
# defined, so `DbUrl` exists by the time database.yml renders; it lives in an
# autoload-ignored lib subdir (see config/application.rb) and has no app/ deps.
#
# #834 — DB_CREDENTIALS (the structured Secrets Manager RDS secret) takes
# precedence over DATABASE_URL, which takes precedence over SPARC_DB_*.
module DbUrl
  DEFAULT_NAME = "ssp_tpr_manager_production"
  DEFAULT_USER = "ssp_tpr_manager"

  # `extend self` (matching SparcConfig) rather than `module_function`, so the
  # methods are the module's public API — database.yml calls DbUrl.database etc.
  extend self

  # Components of DATABASE_URL, or {} when it is unset or unparseable. Not
  # memoized: ENV can differ between the assets:precompile build and runtime,
  # and database.yml is rendered rarely enough that re-parsing is free.
  def components
    url = ENV.fetch("DATABASE_URL", nil)
    return {} if url.nil? || url.empty?

    ActiveRecord::DatabaseConfigurations::ConnectionUrlResolver.new(url).to_hash
  rescue StandardError
    # A malformed DATABASE_URL must not crash boot with a cryptic YAML/ERB error.
    # Fall back to SPARC_DB_* / defaults; Rails' own merge of DATABASE_URL into
    # primary will surface the real error clearly.
    {}
  end

  # Components of DB_CREDENTIALS, or {} when unset or unusable.
  #
  # This is the AWS Secrets Manager RDS secret shape
  # ({host,port,dbname,username,password}), injected by ECS `secrets`→`valueFrom`
  # and read at BOOT. That is the point of #834: DATABASE_URL is rendered at
  # deploy time and therefore pins the password, so a Secrets Manager rotation
  # does not take effect until the next redeploy. Reading the secret at boot
  # means a rotated password is picked up on the next task restart with no IaC
  # change.
  #
  # Re-parsed whenever the raw value changes rather than memoized outright:
  # `components` is deliberately not memoized because ENV differs between the
  # assets:precompile build and runtime, and this must behave the same way. The
  # cache exists only so a malformed secret warns once instead of ~20 times
  # (four databases x five accessors).
  def credentials
    raw = ENV.fetch("DB_CREDENTIALS", nil).to_s
    return {} if raw.empty?
    return @credentials if defined?(@credentials) && @credentials_raw == raw

    @credentials_raw = raw
    @credentials = parse_credentials(raw)
  end

  def database = credentials[:database] || components[:database] || ENV.fetch("SPARC_DB_NAME", DEFAULT_NAME)
  def username = credentials[:username] || components[:username] || ENV.fetch("SPARC_DB_USER", DEFAULT_USER)
  def host     = credentials[:host]     || components[:host]     || ENV.fetch("SPARC_DB_HOST", "localhost")
  def port     = credentials[:port]     || components[:port]     || ENV.fetch("SPARC_DB_PORT", 5432)

  # Raised when production resolves no database password. Deliberately a boot
  # failure and not a warning — see `password` below.
  class MissingPasswordError < StandardError; end

  # The one escape hatch, named so it cannot be set by accident. Mirrors
  # SPARC_LOG_CREDENTIALS (#834): a deliberate, loudly-warned opt-out rather
  # than a silent default.
  ALLOW_EMPTY_PASSWORD_VAR = "SPARC_DB_ALLOW_EMPTY_PASSWORD"

  # #849 — fail closed rather than connect unauthenticated.
  #
  # Every other member of the SPARC_DB_* block has a sane default, so an unset
  # one is merely wrong. An unset password is different in kind: nil is passed
  # to libpq, and a PostgreSQL server configured for `trust` authentication
  # ACCEPTS it. The app then starts, serves traffic, and passes every health
  # check while connected to an unauthenticated database. #834 added a boot
  # warning for this, but a warning is not a control — the operator who missed
  # the ECS `secrets` entry in the first place is not reading the log that says
  # so.
  #
  # So production refuses to start. The point is not validation for its own
  # sake: it is that an operator should not be able to run SPARC insecurely by
  # OMISSION. Declaring it explicitly is still allowed (see the escape hatch),
  # because a passwordless connection is legitimate under RDS IAM
  # authentication — that is a decision, not an oversight, and the distinction
  # is the whole design.
  #
  # Development and test are untouched. A local PostgreSQL on `trust` auth is
  # both legitimate and ubiquitous, and this must not become a dev papercut.
  # Same precedent as the sslmode floor above: strict in production, permissive
  # elsewhere.
  #
  # Checked on the RESOLVED password rather than per-source, so it also catches
  # the case that is hardest to notice — DB_CREDENTIALS rejected as malformed
  # (which only warns) falling through to a SPARC_DB_* block that has no
  # password either.
  def password
    resolved = resolved_password
    return resolved unless resolved.nil?
    return nil unless password_required?

    raise MissingPasswordError, missing_password_message
  end

  # Each candidate goes through `presence`, which the previous implementation
  # did not do. `ENV.fetch("SPARC_DB_PASSWORD", nil)` returns "" for an
  # explicitly-empty variable, and "" is TRUTHY in Ruby — so an empty
  # SPARC_DB_PASSWORD used to short-circuit the `||` chain and be handed to
  # libpq as a real (empty) password, silently beating the fallbacks behind it.
  def resolved_password
    presence(credentials[:password]) ||
      presence(components[:password]) ||
      presence(ENV.fetch("SPARC_DB_PASSWORD", nil)) ||
      presence(ENV.fetch("SSP_TPR_MANAGER_DATABASE_PASSWORD", nil))
  end

  # One credential source wins outright (#834).
  #
  # Rails merges DATABASE_URL into `primary` ONLY. database.yml derives all four
  # logical databases — primary and the Solid cache/queue/cable, all on the SAME
  # RDS instance — from the methods above. So if both sources are set, `primary`
  # would end up on the stale deploy-time password while cache/queue/cable used
  # the rotated one: the app half-connects.
  #
  # Removing DATABASE_URL is the whole fix. There is then nothing for Rails to
  # merge, database.yml is the single source for all four, and no URL has to be
  # rebuilt — which also means no password percent-encoding, and so no chance of
  # the encoding being wrong. Nothing outside this module reads DATABASE_URL.
  def reconcile_database_url!
    return if credentials.empty?
    return if ENV.fetch("DATABASE_URL", nil).to_s.empty?

    # Remembered because the removal destroys the evidence: nothing downstream
    # could otherwise tell that a DATABASE_URL was ever set, so the boot posture
    # check would silently under-report the conflict it exists to surface.
    @discarded_database_url = true
    ENV.delete("DATABASE_URL")
  end

  def discarded_database_url? = @discarded_database_url == true

  # Which of the three sources actually supplied the connection.
  #
  # Precedence is deliberate but INVISIBLE at runtime: an operator who sets
  # SPARC_DB_HOST alongside DB_CREDENTIALS gets the credentials one and no
  # indication their variable was ignored. `zz_database_config_posture.rb`
  # reports this at boot so "which of these is actually in effect?" has an
  # answer in the logs rather than requiring someone to read this file.
  SOURCES = %i[db_credentials database_url sparc_db_vars defaults].freeze

  def source
    return :db_credentials if credentials.any?
    return :database_url   if components.any?
    return :sparc_db_vars  if sparc_db_vars_set.any?

    :defaults
  end

  # Sources that are configured but LOSE to the one in effect.
  def overridden_sources
    winner = source
    others = []
    others << :database_url if winner != :database_url && (components.any? || discarded_database_url?)
    others << :sparc_db_vars if winner != :sparc_db_vars && sparc_db_vars_set.any?
    others
  end

  SPARC_DB_VARS = %w[
    SPARC_DB_HOST SPARC_DB_PORT SPARC_DB_NAME SPARC_DB_USER SPARC_DB_PASSWORD
  ].freeze

  def sparc_db_vars_set = SPARC_DB_VARS.select { |name| ENV.fetch(name, nil).to_s.strip.presence }

  # The SPARC_DB_* block has no all-or-nothing guard of its own — an unset
  # member silently takes a built-in default. That is merely wrong for host,
  # name and user, which is why they are still only WARNED about; #849 made the
  # password the exception, because defaulting it means connecting with no
  # credential at all. `port` is excluded: 5432 is an unambiguous default, not
  # an omission.
  def sparc_db_vars_missing
    return [] if sparc_db_vars_set.empty?

    (SPARC_DB_VARS - [ "SPARC_DB_PORT" ]) - sparc_db_vars_set
  end

  # Secondary databases keep the historical _cache/_queue/_cable suffixes.
  def cache_database = "#{database}_cache"
  def queue_database = "#{database}_queue"
  def cable_database = "#{database}_cable"

  # Whether a blank resolved password is a refusal or merely permitted.
  #
  # Public so the boot posture check and the specs can ask the question without
  # triggering the raise as a side effect.
  def password_required?
    return false unless production?
    # assets:precompile boots the production environment purely to build assets,
    # with no database configured and none needed. Refusing here would break the
    # IMAGE BUILD rather than a deployment — the same trap the other posture
    # checks guard against.
    return false unless ENV.fetch("SECRET_KEY_BASE_DUMMY", nil).to_s.empty?
    return false if allow_empty_password?

    true
  end

  def allow_empty_password?
    %w[true 1 yes].include?(ENV.fetch(ALLOW_EMPTY_PASSWORD_VAR, "").to_s.strip.downcase)
  end

  private

  # Matches config/database.yml's own production test (`ENV['RAILS_ENV'] ==
  # 'production'`) rather than Rails.env, for two reasons: this file is required
  # from config/application.rb before the application class exists, and the
  # sslmode floor next door keys off exactly this. If the two disagreed, a
  # deployment could floor its TLS mode but not its password, or the reverse.
  def production? = ENV.fetch("RAILS_ENV", nil) == "production"

  # The message IS the feature. Whoever hits this is mid-deploy, looking at a
  # container that will not start, and needs to know which variable to set
  # without reading this file — so it names the resolved source, the specific
  # omission, every accepted way to fix it, and the explicit opt-out.
  def missing_password_message
    <<~MESSAGE
      [SPARC] Refusing to start: no database password is configured.

      Resolved configuration source: #{source}
      #{missing_password_detail}

      SPARC will not connect to a production database without a password. A
      PostgreSQL server configured for `trust` authentication would ACCEPT an
      empty password, so this would otherwise boot, pass health checks, and
      serve traffic against an unauthenticated database connection.

      Set one of the following (precedence: DB_CREDENTIALS > DATABASE_URL > SPARC_DB_*):

        SPARC_DB_PASSWORD=...    alongside SPARC_DB_HOST / SPARC_DB_NAME / SPARC_DB_USER
        DB_CREDENTIALS=...       the Secrets Manager RDS secret, as JSON
        DATABASE_URL=...         postgres://user:password@host:5432/database

      If this database genuinely authenticates WITHOUT a password — RDS IAM
      authentication being the real case — declare that explicitly:

        #{ALLOW_EMPTY_PASSWORD_VAR}=true

      See docs/ENVIRONMENT_VARIABLES.md for the full configuration reference.
    MESSAGE
  end

  def missing_password_detail
    case source
    when :sparc_db_vars
      missing = sparc_db_vars_missing
      "Unset: #{missing.any? ? missing.join(', ') : 'SPARC_DB_PASSWORD'}"
    when :database_url
      "DATABASE_URL is set but carries no password component."
    when :db_credentials
      # Unreachable in practice: parse_credentials rejects a secret missing any
      # member, so :db_credentials implies a password. Kept so a future change
      # to that validation cannot produce a message with an empty detail line.
      "DB_CREDENTIALS resolved without a password."
    else
      "No database configuration is set at all (DB_CREDENTIALS, DATABASE_URL " \
      "and SPARC_DB_* are all unset), so the built-in development defaults applied."
    end
  end

  def parse_credentials(raw)
    parsed = JSON.parse(raw)
    unless parsed.is_a?(Hash)
      return warn_and_ignore("DB_CREDENTIALS is #{parsed.class}, expected a JSON object")
    end

    fields = {
      database: presence(parsed["dbname"]),
      username: presence(parsed["username"]),
      password: presence(parsed["password"]),
      host:     presence(parsed["host"]),
      port:     port_number(parsed["port"]) || 5432
    }

    # All or nothing. A partial secret silently mixed with DATABASE_URL or
    # SPARC_DB_* is the worst outcome available: it connects, to some blend of
    # two credentials, and the failure surfaces somewhere else entirely. Port is
    # the one optional field — Postgres has an unambiguous default.
    missing = fields.select { |_, v| v.nil? }.keys
    return warn_and_ignore("DB_CREDENTIALS is missing #{missing.join(', ')}") if missing.any?

    fields
  rescue JSON::ParserError => e
    warn_and_ignore("DB_CREDENTIALS is not valid JSON (#{e.message})")
  end

  # Warns rather than raising, matching the DATABASE_URL path above and the
  # database TLS posture check: a bad value must not turn into a cryptic
  # YAML/ERB error at boot. It is loud because the fallback — localhost with
  # SPARC_DB_* defaults — surfaces later as a confusing connection failure that
  # looks nothing like "the secret is malformed". No value is echoed; the secret
  # holds the password.
  def warn_and_ignore(message)
    warn("[SPARC] #{message}. Falling back to DATABASE_URL / SPARC_DB_*.")
    {}
  end

  def presence(value)
    return nil if value.nil?

    string = value.to_s.strip
    string.empty? ? nil : string
  end

  # Secrets Manager writes `port` as a number, but hand-maintained secrets
  # sometimes quote it. Returned as an Integer either way so it matches what
  # Rails' ConnectionUrlResolver yields for DATABASE_URL.
  def port_number(value)
    string = presence(value)
    return nil if string.nil? || !string.match?(/\A\d+\z/)

    string.to_i
  end
end
