# frozen_string_literal: true

# Session cookie configuration.
#
# SPARC intentionally relies on Rails' default cookie_store WITHOUT setting
# a `domain:` attribute. This produces a **host-only** Set-Cookie response
# (no Domain= attribute), which per RFC 6265 §5.1.3 makes the browser send
# the cookie ONLY to the exact host that set it.
#
# DO NOT ADD `domain:` HERE WITHOUT UNDERSTANDING THE TRADEOFF:
#
#   domain: "sparc.risk-sentinel.org"  →  cookie sent to sparc.* AND
#                                         every subdomain like
#                                         userdata.sparc.risk-sentinel.org
#                                         (defeats the #515 cookieless-
#                                         blob-subdomain protection)
#
#   no domain attribute               →  cookie sent only to the exact
#                                         host (sparc.risk-sentinel.org),
#                                         NOT to subdomains — what we want
#
# This file exists to document the decision; the actual session config
# stays at Rails defaults. Verified in prod: curl -sI returns
# Set-Cookie: _ssp_tpr_manager_session=...; path=/; secure; httponly;
# samesite=lax — no Domain= attribute. Good.
#
# References:
#   #515 — cookieless userdata subdomain
#   RFC 6265 §5.1.3 (cookie domain matching)
#   MITRE Vulcan uses the same host-only pattern.
#
# (If session storage needs to move from cookie_store to a server-side
# adapter like ActiveRecord for revocability, that's a separate concern
# from cookie scoping. The cookie-scope rules above apply regardless of
# storage backend.)
#
# ── Cookie lifetime (#649, epic #650) ───────────────────────────────────────
#
# Bind the session cookie's own lifetime to the configured idle timeout. The
# app-level check_session_timeout (app/controllers/concerns/authentication.rb)
# is the PRIMARY, sliding (idle) enforcement; expire_after is a defense-in-depth
# backstop so a stale cookie can't be replayed past the window even if that
# check were ever bypassed. Both honour the SINGLE timeout var — no parallel
# timeout is introduced. Because last_active_at is rewritten on every
# non-expired request, the session is re-issued each response and expire_after
# slides with activity (it won't drop the cookie out from under an active user).
#
# Read ENV directly, NOT SparcConfig: initializers run before Zeitwerk indexes
# app/ during assets:precompile / the Docker build, so referencing the
# autoloaded SparcConfig here fails. The value mirrors SparcConfig.session_timeout
# (SPARC_SESSION_TIMEOUT_MINUTES, default 60).
#
# `key:` is set EXPLICITLY to the app's historical cookie name. Calling
# session_store at all overrides Rails' app-name-derived default key, reverting
# it to the bare "_session_id" — which would rename the cookie and break the
# from_token bridge / Playwright auto-detection (it keys off "*_session"). We do
# NOT set `domain:`, preserving the host-only cookie documented above (#515).
Rails.application.config.session_store :cookie_store,
  key: "_ssp_tpr_manager_session",
  expire_after: ENV.fetch("SPARC_SESSION_TIMEOUT_MINUTES", "60").to_i.minutes
