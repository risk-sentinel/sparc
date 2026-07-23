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

  def database = components[:database] || ENV.fetch("SPARC_DB_NAME", DEFAULT_NAME)
  def username = components[:username] || ENV.fetch("SPARC_DB_USER", DEFAULT_USER)
  def host     = components[:host]     || ENV.fetch("SPARC_DB_HOST", "localhost")
  def port     = components[:port]     || ENV.fetch("SPARC_DB_PORT", 5432)

  def password
    components[:password] ||
      ENV.fetch("SPARC_DB_PASSWORD", nil) ||
      ENV.fetch("SSP_TPR_MANAGER_DATABASE_PASSWORD", nil)
  end

  # Secondary databases keep the historical _cache/_queue/_cable suffixes.
  def cache_database = "#{database}_cache"
  def queue_database = "#{database}_queue"
  def cable_database = "#{database}_cable"
end
