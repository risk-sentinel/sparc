# frozen_string_literal: true

# WebAuthn / FIDO2 relying-party configuration (#779).
#
# Uses ENV directly rather than the autoloaded SparcConfig, so it is safe during
# assets:precompile (which runs before Zeitwerk). WebAuthn is a gem constant, so
# no deferral is needed.
#
# `allowed_origins` MUST match the browser's origin exactly (scheme + host +
# port). Behind caddy/ALB with assume_ssl the effective origin is https://<host>,
# so SPARC_APP_URL should carry the externally-visible URL. rp_id defaults to that
# origin's host; override only to scope credentials to a parent domain.
origin = ENV.fetch("SPARC_APP_URL", "http://localhost:3000")

WebAuthn.configure do |config|
  config.allowed_origins = [ origin ]
  config.rp_name = ENV.fetch("SPARC_FIDO2_RP_NAME", "SPARC")
  rp_id = ENV.fetch("SPARC_FIDO2_RP_ID", nil).presence
  config.rp_id = rp_id if rp_id
  # Give the ceremony room for PIN/biometric entry.
  config.credential_options_timeout = 120_000
end
