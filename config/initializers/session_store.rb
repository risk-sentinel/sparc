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
