# frozen_string_literal: true

# #1098 — at boot, whether OIDC sign-in is on and whether an egress proxy
# applies to the issuer. No network call; see OidcEgressPosture.
#
# NIST 800-53: CM-6 (configuration settings reported at start-up), AC-4.
Rails.application.config.after_initialize do
  # `assets:precompile` boots the app purely to build assets (#785).
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  line = OidcEgressPosture.line
  Rails.logger.info(line) if line
end
