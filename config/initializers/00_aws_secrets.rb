# frozen_string_literal: true

# AWS Secrets Manager — App-Config JSON Blob Unpacker
#
# When Secrets Manager is enabled, this initializer runs early in boot
# (00_ prefix ensures it loads before other initializers that read ENV) to
# fetch a JSON blob from Secrets Manager and inject each key-value pair
# into ENV. Existing ENV vars take precedence — they are never overwritten.
#
# #1120 — enabled by SPARC_AWS_SECRETS_ENABLED=true, OR inferred from
# SPARC_APP_CONFIG_SECRET_ARN being set; an explicit
# SPARC_AWS_SECRETS_ENABLED=false still wins. This runs before autoload, so it
# cannot call SparcConfig.aws_secrets_enabled? and repeats that inference.
# Keep the two in step (spec/initializers/aws_secrets_spec.rb loads this file).
#
# Two-secret strategy (aligned with sparc-iac #22):
#   Secret 1: sparc-{env}/admin-credentials  — break-glass admin password (MFA-gated, not read by app)
#   Secret 2: sparc-{env}/app-config          — JSON blob with all other config (read here)
#
# NIST 800-53 Controls:
#   SC-12 Cryptographic Key Establishment (SECRET_KEY_BASE via Secrets Manager)
#   SC-28 Protection of Information at Rest (secrets KMS-encrypted, never on disk)
#   CM-6  Configuration Settings (env var injection from centralized secret)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md

# #1133 — the boot cannot load its configuration from Secrets Manager. Defined
# here because this file runs before autoload.
module SparcSecrets
  class Error < StandardError; end
end

raw_secrets_enabled = ENV.fetch("SPARC_AWS_SECRETS_ENABLED", nil)
secrets_enabled =
  if raw_secrets_enabled.present?
    raw_secrets_enabled == "true"
  else
    ENV.fetch("SPARC_APP_CONFIG_SECRET_ARN", nil).present?
  end

if secrets_enabled
  # Required here, not at the top (#1133): the SDK is loaded only when this
  # deployment uses Secrets Manager, and this file runs before autoload.
  require "aws-sdk-secretsmanager"
  require "json"

  # Explicit nil default: the blank? check below raises a specific,
  # actionable message. A no-default ENV.fetch would pre-empt it with an
  # opaque KeyError.
  secret_arn = ENV.fetch("SPARC_APP_CONFIG_SECRET_ARN", nil)

  if secret_arn.blank?
    raise SparcSecrets::Error, <<~MSG
      SPARC_AWS_SECRETS_ENABLED=true but SPARC_APP_CONFIG_SECRET_ARN is not set.
      Set the ARN of the app-config secret in Secrets Manager, or disable
      Secrets Manager integration with SPARC_AWS_SECRETS_ENABLED=false.
    MSG
  end

  begin
    region = ENV.fetch("SPARC_AWS_REGION", ENV.fetch("AWS_REGION", "us-east-1"))
    client = Aws::SecretsManager::Client.new(region: region)
    response = client.get_secret_value(secret_id: secret_arn)
    config = JSON.parse(response.secret_string)

    injected = []
    config.each do |key, value|
      unless ENV.key?(key)
        ENV[key] = value.to_s
        injected << key
      end
    end

    # Log which keys were injected (never log values)
    if defined?(Rails.logger) && Rails.logger
      Rails.logger.info("[SparcSecrets] Loaded #{config.size} keys from Secrets Manager, " \
                        "injected #{injected.size} (#{config.size - injected.size} already set in ENV)")
    else
      $stdout.puts("[SparcSecrets] Loaded #{config.size} keys from Secrets Manager, " \
                   "injected #{injected.size}")
    end
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException => e
    raise SparcSecrets::Error, "SPARC_APP_CONFIG_SECRET_ARN references a secret that does not exist: #{e.message}"
  rescue Aws::SecretsManager::Errors::AccessDeniedException => e
    raise SparcSecrets::Error, "ECS task role lacks secretsmanager:GetSecretValue permission: #{e.message}"
  rescue JSON::ParserError => e
    raise SparcSecrets::Error, "SPARC_APP_CONFIG_SECRET_ARN secret is not valid JSON: #{e.message}"
  rescue Aws::Errors::ServiceError => e
    raise SparcSecrets::Error, "Failed to retrieve secret from Secrets Manager: #{e.class} — #{e.message}"
  end
end
