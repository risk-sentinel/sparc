# frozen_string_literal: true

# Rack::Attack — rate-limiting middleware (#513).
#
# Throttle buckets (all operator-tunable via SparcConfig / SPARC_RATE_LIMIT_*):
#
#   - uploads/5min/ip       — per-IP cap on upload endpoints (default 30/5min)
#   - uploads/hour/user     — per-user cap on upload endpoints (default 100/hr)
#   - api/writes/min/token  — per-API-token cap on /api/v1 write methods (default 300/min)
#   - logins/failures/min/ip — per-IP cap on failed login attempts (default 5/min)
#
# Safelist (bypasses all throttles): CIDRs in SPARC_RATE_LIMIT_SAFELIST_CIDRS.
# Defaults to loopback (127.0.0.1, ::1) so dev/test never hit limits.
#
# Cache backing: Rails.cache. In prod that's solid_cache (DB-backed; counters
# survive single-instance restarts and are coherent across pods). In dev it's
# memory_store. In test the initializer self-disables via Rack::Attack.enabled.
#
# Throttle hits log to Rails.logger with [rack-attack] prefix (ingested by
# CloudWatch in prod). No AuditEvent record per hit — would generate excessive
# noise under a bot storm; logs are the source of truth for triage.

require "ipaddr"

Rack::Attack.cache.store = Rails.cache

# Self-disable in test (avoids flaky throttle hits across parallel specs)
# and when the operator-level kill switch is set.
#
# Deferred to after_initialize because SparcConfig is autoloaded under
# app/models; referencing it at the top of an initializer fails during
# assets:precompile / Docker build (autoload not ready yet). At request
# time SparcConfig is always resolvable; the throttle lambdas below
# already rely on the same lazy resolution.
Rails.application.config.after_initialize do
  Rack::Attack.enabled = !Rails.env.test? && SparcConfig.rate_limiting_enabled?
end

# ── Safelists ──────────────────────────────────────────────────────────────

Rack::Attack.safelist("safelist: trusted CIDRs") do |req|
  ip = req.ip
  SparcConfig.rate_limit_safelist_cidrs.any? do |cidr|
    IPAddr.new(cidr).include?(ip)
  rescue IPAddr::InvalidAddressError, IPAddr::Error
    false
  end
end

# ── Helpers ────────────────────────────────────────────────────────────────

def rack_attack_upload_request?(req)
  return false unless %w[POST PUT PATCH].include?(req.request_method)
  # Document-create routes follow /<plural>_documents or /evidences pattern.
  # Match anything that looks like a multipart/form upload on a SPARC create path.
  path = req.path
  path.match?(%r{\A/(ssp|sar|sap|poam|cdef|profile)_documents\z}) ||
    path.match?(%r{\A/converters/import\z}) ||
    path.match?(%r{\A/control_catalogs/import\z}) ||
    path.match?(%r{\A/profiles/avatar\z}) ||
    path.match?(%r{\A/evidences\z})
end

def rack_attack_api_write_request?(req)
  return false unless %w[POST PUT PATCH DELETE].include?(req.request_method)
  req.path.start_with?("/api/v1/")
end

def rack_attack_api_token_id(req)
  # Authorization: Bearer <token> — use a stable prefix as the discriminator
  # (don't log the full token; first 12 chars is enough to group requests).
  auth = req.env["HTTP_AUTHORIZATION"].to_s
  return nil unless auth.start_with?("Bearer ")
  token = auth.delete_prefix("Bearer ").strip
  return nil if token.empty?
  token[0, 12]
end

def rack_attack_login_failure_request?(req)
  return false unless req.request_method == "POST"
  # Local login form posts to /login; failed OIDC callbacks land on /auth/failure;
  # passwordless FIDO2 sign-in posts to /session/webauthn (#779).
  req.path == "/login" || req.path == "/auth/failure" || req.path == "/session/webauthn"
end

def rack_attack_csp_report_request?(req)
  req.request_method == "POST" && req.path == "/security/csp-violations"
end

# ── Throttles ──────────────────────────────────────────────────────────────

Rack::Attack.throttle("uploads/5min/ip",
                      limit: ->(_req) { SparcConfig.rate_limit_uploads_per_5min_per_ip },
                      period: 5.minutes) do |req|
  req.ip if rack_attack_upload_request?(req)
end

Rack::Attack.throttle("uploads/hour/user",
                      limit: ->(_req) { SparcConfig.rate_limit_uploads_per_hour_per_user },
                      period: 1.hour) do |req|
  user = req.env["warden"]&.user
  user&.id if user && rack_attack_upload_request?(req)
end

Rack::Attack.throttle("api/writes/min/token",
                      limit: ->(_req) { SparcConfig.rate_limit_api_writes_per_minute },
                      period: 1.minute) do |req|
  rack_attack_api_token_id(req) if rack_attack_api_write_request?(req)
end

Rack::Attack.throttle("logins/failures/min/ip",
                      limit: ->(_req) { SparcConfig.rate_limit_login_failures_per_minute },
                      period: 1.minute) do |req|
  req.ip if rack_attack_login_failure_request?(req)
end

# #573 — dedicated bucket for the API → session bridge. Same family
# of throttle as login failures: stricter than general api/writes
# because a successful bridge yields a session cookie. The IP is
# the discriminator (not the token), so a token brute-force from
# one IP can't sidestep by rotating tokens.
Rack::Attack.throttle("api/sessions_from_token/min/ip",
                      limit: ->(_req) { SparcConfig.rate_limit_login_failures_per_minute },
                      period: 1.minute) do |req|
  req.ip if req.path == "/api/v1/sessions/from_token" && req.request_method == "POST"
end

# #528/#650 — CSP violation report beacon. Per-IP throttle so the log sink
# can't be flooded. Over-limit reports are dropped with a 429; the browser
# silently ignores the response (a report beacon expects nothing back).
Rack::Attack.throttle("csp-reports/min/ip",
                      limit: ->(_req) { SparcConfig.rate_limit_csp_reports_per_minute },
                      period: 1.minute) do |req|
  req.ip if rack_attack_csp_report_request?(req)
end

# ── 429 response ───────────────────────────────────────────────────────────

Rack::Attack.throttled_responder = lambda do |request|
  match_data  = request.env["rack.attack.match_data"] || {}
  retry_after = (match_data[:period] || 60).to_i
  bucket      = request.env["rack.attack.matched"]

  payload = {
    error: "Too many requests",
    code: "rate_limit_exceeded",
    bucket: bucket,
    retry_after: retry_after
  }

  [
    429,
    {
      "Content-Type"  => "application/json",
      "Retry-After"   => retry_after.to_s,
      "X-RateLimit-Bucket" => bucket.to_s
    },
    [ payload.to_json ]
  ]
end

# ── Throttle-hit logging (CloudWatch-ingestible) ───────────────────────────

ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  discriminator = payload[:discriminator] || req.env["rack.attack.discriminator"]
  Rails.logger.warn(
    "[rack-attack] THROTTLED bucket=#{req.env['rack.attack.matched']} " \
    "discriminator=#{discriminator} ip=#{req.ip} method=#{req.request_method} path=#{req.path}"
  )
end
