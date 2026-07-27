# frozen_string_literal: true

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
  require "json"

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

  def password
    credentials[:password] ||
      components[:password] ||
      ENV.fetch("SPARC_DB_PASSWORD", nil) ||
      ENV.fetch("SSP_TPR_MANAGER_DATABASE_PASSWORD", nil)
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

    ENV.delete("DATABASE_URL")
  end

  # Secondary databases keep the historical _cache/_queue/_cable suffixes.
  def cache_database = "#{database}_cache"
  def queue_database = "#{database}_queue"
  def cable_database = "#{database}_cable"

  private

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
