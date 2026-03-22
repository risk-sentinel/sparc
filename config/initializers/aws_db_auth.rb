# frozen_string_literal: true

# AWS IAM Database Authentication
#
# When SPARC_AWS_IAM_DB_AUTH=true, this initializer patches the PostgreSQL
# adapter to generate short-lived IAM auth tokens (15 minutes) instead of
# using a static database password. This eliminates the need for a DB
# password in Secrets Manager or ENV — the ECS task role provides access.
#
# Prerequisites:
#   - RDS instance with iam_database_authentication_enabled = true
#   - ECS task role with rds-db:connect permission
#   - DB user created with: CREATE USER sparc WITH LOGIN; GRANT rds_iam TO sparc;
#
# NIST 800-53 Controls:
#   IA-5  Authenticator Management (auto-rotating 15-min tokens)
#   SC-12 Cryptographic Key Establishment (IAM-signed auth tokens)
#   SC-28 Protection of Information at Rest (no static DB password stored)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md

if ENV["SPARC_AWS_IAM_DB_AUTH"] == "true"
  require "aws-sdk-rds"

  Rails.application.config.after_initialize do
    region = ENV.fetch("SPARC_AWS_REGION", ENV.fetch("AWS_REGION", "us-east-1"))

    generator = Aws::RDS::AuthTokenGenerator.new(
      credentials: Aws::ECSCredentials.new
    )

    # Patch PostgreSQL adapter to refresh IAM auth token on each new connection.
    # IAM tokens are valid for 15 minutes — well within connection pool lifetime.
    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(Module.new do
      define_method(:configure_connection) do
        db_config = ActiveRecord::Base.connection_db_config.configuration_hash
        host = db_config[:host] || "localhost"
        port = db_config[:port] || 5432
        username = db_config[:username] || "sparc"

        begin
          token = generator.auth_token(
            region: region,
            endpoint: "#{host}:#{port}",
            user_name: username
          )
          @raw_connection.exec("SET SESSION AUTHORIZATION DEFAULT") rescue nil
          @raw_connection = PG.connect(
            @raw_connection.conninfo_hash.merge(password: token)
          )
        rescue Aws::Errors::ServiceError => e
          Rails.logger.error("[AwsDbAuth] IAM token generation failed: #{e.message}")
          # Fall through to existing password if IAM auth fails
        end

        super()
      end
    end)

    Rails.logger.info("[AwsDbAuth] IAM database authentication enabled for region #{region}")
  end
end
