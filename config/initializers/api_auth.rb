# frozen_string_literal: true

# Validates SPARC_API_AUTH configuration at boot time.
# Fails fast with a clear error if the mode is invalid or required
# companion env vars are missing.
#
# Valid modes:
#   local  — SPARC-issued Bearer tokens only (default)
#   oidc   — OIDC/Okta JWT tokens only
#   hybrid — JWTs for humans + SPARC tokens for service accounts
#
# NIST 800-53 Controls:
#   CM-6 Configuration Settings (boot-time validation of auth mode)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md

Rails.application.config.after_initialize do
  mode = SparcConfig.api_auth_mode

  unless SparcConfig::API_AUTH_MODES.include?(mode)
    raise <<~MSG
      Invalid SPARC_API_AUTH value: "#{mode}"
      Valid values: #{SparcConfig::API_AUTH_MODES.join(', ')}
    MSG
  end

  if %w[oidc hybrid].include?(mode) && SparcConfig.oidc_issuer_url.blank?
    raise <<~MSG
      SPARC_API_AUTH=#{mode} requires SPARC_OIDC_ISSUER_URL to be set.
      The API needs the OIDC issuer URL to validate JWT tokens.
      Set SPARC_OIDC_ISSUER_URL or change SPARC_API_AUTH to "local".
    MSG
  end

  Rails.logger.info("[SPARC] API authentication mode: #{mode}")
end
