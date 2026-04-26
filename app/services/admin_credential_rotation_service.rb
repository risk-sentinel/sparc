# Rotates the SPARC instance admin's password.
#
# Two callers:
#
#   * lib/tasks/admin.rake → sparc:rotate_admin_credentials
#       Manual / break-glass rotation initiated from inside the SPARC
#       container. Generates a new plaintext, updates DB, pushes to
#       AWS Secrets Manager so ops can retrieve via Console.
#
#   * Api::V1::Admin::CredentialsController#refresh (#403)
#       Lambda-driven rotation. The Lambda has already written the
#       plaintext to SM (AWSPENDING) before calling SPARC; the controller
#       only needs the DB-update path. Pass `push_to_secrets_manager:
#       false` to skip the SM round-trip.
#
# In all paths the password's bcrypt digest is the only thing stored on
# disk inside SPARC. Plaintext exists only in memory for the duration of
# the rotation and (via SM) in AWS-managed encrypted storage.
#
# NIST 800-53:
#   IA-4   Identifier Management
#   IA-5   Authenticator Management
#   AC-2   Account Management (lifecycle event audited)
#   AU-2   Audit Events (one row per rotation)
#   AU-9   Protection of Audit Information (audit record never includes plaintext)
#   SC-12  Cryptographic Key Establishment (random generation, KMS-encrypted SM)
class AdminCredentialRotationService
  Result = Struct.new(:success, :version_id, :plaintext, :error, :status_code, keyword_init: true) do
    def success? = success
  end

  PASSWORD_LENGTH = 24

  # Generate-and-rotate path used by the rake task. Returns the plaintext
  # in the Result so the caller can print it (rake task only — never log
  # the plaintext from a request handler).
  def self.rotate_from_local!(actor: nil, source: "rake", admin_email: nil)
    plaintext = SecureRandom.alphanumeric(PASSWORD_LENGTH)
    result = apply!(plaintext: plaintext, actor: actor, source: source,
                    admin_email: admin_email, push_to_secrets_manager: true)
    result[:plaintext] = plaintext if result.success?
    result
  end

  # Apply a plaintext password supplied by the caller. Used by the API
  # controller (Lambda-driven rotation): the Lambda already wrote the
  # plaintext to SM, so we skip the SM round-trip here.
  def self.apply!(plaintext:, actor: nil, source: "api", admin_email: nil,
                  push_to_secrets_manager: false)
    new(plaintext: plaintext, actor: actor, source: source,
        admin_email: admin_email,
        push_to_secrets_manager: push_to_secrets_manager).call
  end

  def initialize(plaintext:, actor:, source:, admin_email: nil,
                 push_to_secrets_manager: false)
    @plaintext               = plaintext
    @actor                   = actor
    @source                  = source
    @admin_email             = admin_email || ENV.fetch("SPARC_ADMIN_EMAIL", "admin@sparc.local")
    @push_to_secrets_manager = push_to_secrets_manager
    @version_id              = nil
  end

  def call
    return blank_result    if @plaintext.to_s.length < 8
    return missing_admin   unless admin

    if @push_to_secrets_manager
      sm_result = push_to_secrets_manager!
      return sm_result unless sm_result.success?

      @version_id = sm_result.version_id
    end

    update_admin!

    AuditEvent.log(
      user: admin,
      action: "admin_credential_rotated",
      provider: "local",
      metadata: {
        email:      admin.email,
        source:     @source,
        actor_id:   @actor&.id,
        version_id: @version_id
      }.compact
    )

    Result.new(success: true, version_id: @version_id)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success: false, status_code: :unprocessable_entity,
               error: e.record.errors.full_messages.join(", "))
  end

  private

  def admin
    @admin ||= User.find_by(email: @admin_email.downcase.strip)
  end

  def update_admin!
    User.transaction do
      admin.lock!
      admin.assign_attributes(
        password:              @plaintext,
        password_confirmation: @plaintext,
        must_reset_password:   true,
        password_changed_at:   Time.current
      )
      admin.admin = true
      admin.save!
    end
  end

  def push_to_secrets_manager!
    arn = ENV["SPARC_ADMIN_CREDENTIALS_SECRET_ARN"].presence
    return Result.new(success: false, status_code: :failed_dependency,
                      error: "SPARC_ADMIN_CREDENTIALS_SECRET_ARN is not set") if arn.blank?

    require "aws-sdk-secretsmanager"
    region = ENV.fetch("SPARC_AWS_REGION", ENV.fetch("AWS_REGION", "us-east-1"))
    client = Aws::SecretsManager::Client.new(region: region)

    put_response = client.put_secret_value(
      secret_id:      arn,
      secret_string:  { password: @plaintext }.to_json,
      version_stages: [ "AWSCURRENT" ]
    )

    Result.new(success: true, version_id: put_response.version_id)
  rescue Aws::SecretsManager::Errors::AccessDeniedException => e
    Result.new(success: false, status_code: :forbidden,
               error: "ECS task role lacks PutSecretValue: #{e.message}")
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException => e
    Result.new(success: false, status_code: :not_found,
               error: "admin-credentials secret not found: #{e.message}")
  rescue Aws::Errors::ServiceError => e
    Result.new(success: false, status_code: :bad_gateway,
               error: "Secrets Manager error: #{e.class} — #{e.message}")
  end

  def blank_result
    Result.new(success: false, status_code: :unprocessable_entity,
               error: "Password must be at least 8 characters")
  end

  def missing_admin
    Result.new(success: false, status_code: :not_found,
               error: "Admin user with email #{@admin_email} not found")
  end
end
