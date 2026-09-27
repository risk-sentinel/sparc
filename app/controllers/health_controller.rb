# frozen_string_literal: true

# #1151 — the health endpoints SPARC never had.
#
#   GET /up        liveness:  the process is up and routing. No database.
#   GET /up/ready  readiness: the database answers, no migration is pending,
#                  and the schema matches db/schema.rb. 200 or 503.
#
# ── Why ────────────────────────────────────────────────────────────────────
#
# `production.rb` has excluded `/up` from the SSL redirect and silenced its
# logs since the app was generated, and no route ever answered it. The load
# balancer health check in front of a deployment therefore hit NGINX
# (`/nginx-health`), which proves a proxy is listening and knows nothing about
# Rails, the database or the schema. So when v1.16.2 upgraded a database to a
# schema with seven missing columns, every layer reported healthy while every
# boundary page returned 500 (#1147).
#
# `/up/ready` is the signal that was missing: point the load balancer here and
# a container whose schema does not match is taken out of service instead of
# served. The boot gate in `bin/docker-entrypoint` is the first line — a
# container that cannot reconcile never binds its port — and this is the
# second, for drift that appears after boot.
#
# ── What it discloses ──────────────────────────────────────────────────────
#
# Unauthenticated by necessity (a load balancer holds no credentials), so the
# body carries COUNTS only — never a table, column or migration name. The
# detail goes to the log, where an operator can read it and a caller cannot.
#
# Inherits ActionController::Base directly, like Security::CspReportsController:
# no auth gate, session, CSRF token or browser guard applies to a probe, and
# the application controller's chain would turn a probe into a login redirect.
#
# The schema check reads the catalog for every table, so its result is cached
# for CACHE_TTL: a probe every few seconds must not become a query storm. The
# database ping is NOT cached — losing the database is the one change a probe
# must see immediately.
#
# NIST SP 800-53 Rev 5: SI-7 (integrity — the schema matches its declared
# state), CA-7 (continuous monitoring), SC-5 (a probe cannot be amplified into
# load: cached, bounded, read-only).
# rubydre:S7905 ("inherit from ApplicationController") is a false positive here:
# a load-balancer probe carries no session and must not enter the auth chain.
class HealthController < ActionController::Base # NOSONAR(rubydre:S7905)
  CACHE_TTL = 60 # seconds

  @cache = nil
  @cache_lock = Mutex.new

  class << self
    # [pending_migrations, schema_drift], computed at most once per CACHE_TTL.
    def schema_state
      @cache_lock.synchronize do
        now = clock
        @cache = nil if @cache && now - @cache[:at] > CACHE_TTL
        @cache ||= { at: now, value: measure_schema }
        @cache[:value]
      end
    end

    def reset_cache! = @cache_lock.synchronize { @cache = nil }

    # Monotonic, so a wall-clock change cannot pin or flush the cache.
    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    private

    def measure_schema
      pending = ActiveRecord::Base.connection_pool.migration_context.open.pending_migrations.size
      drift = SchemaDriftService.new
      found = drift.drift
      Rails.logger.warn("health: /up/ready not ready\n#{drift.report}") if found.any?
      { pending_migrations: pending, schema_drift: found.size }
    end
  end

  def show
    render json: { status: "ok" }
  end

  def ready
    checks = { database: database_state }
    checks.merge!(self.class.schema_state) if checks[:database] == "ok"
    ok = checks[:database] == "ok" && checks[:pending_migrations].zero? && checks[:schema_drift].zero?

    render json: { status: ok ? "ok" : "unavailable", checks: checks }, status: ok ? :ok : :service_unavailable
  end

  private

  def database_state
    ActiveRecord::Base.connection.select_value("SELECT 1")
    "ok"
  rescue StandardError => e
    Rails.logger.warn("health: /up/ready database check failed (#{e.class}: #{e.message})")
    "unavailable"
  end
end
