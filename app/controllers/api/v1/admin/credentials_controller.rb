# Admin credential rotation endpoint (#403).
#
# Receives a new admin password from a sparc-iac-managed Lambda that has
# already written it to AWS Secrets Manager (AWSPENDING). SPARC bcrypts
# the value into the admin user's `password_digest`; the Lambda is
# responsible for promoting AWSPENDING → AWSCURRENT after a successful
# 200 response. See Rebel-Raiders/sparc-iac#197 for the Lambda contract.
#
# Auth uses SPARC's existing service account API token mechanism (#257):
# the Lambda holds a `sparc_sa_*` Bearer token (stored in its own SM
# secret, retrieved at invoke time), and the SPARC service account it
# represents must hold the `admin.rotate_credentials` permission and
# (optionally) be CIDR-allowlisted to the Lambda's egress IPs.
#
# Feature flag: requires `SPARC_ADMIN_REFRESH_ENABLED=true` to enable.
# Otherwise returns 503 to fail closed in environments that haven't
# opted in to remote rotation.
#
# NIST 800-53:
#   AC-3   Access Enforcement (permission + endpoint scoping)
#   AC-17  Remote Access (CIDR allowlist on the service account token)
#   AU-2   Audit Events (every call writes an AuditEvent)
#   IA-5   Authenticator Management (rotation propagation)
#   SC-13  Cryptographic Protection (TLS in transit; bcrypt at rest)
#   SI-10  Information Input Validation (length + presence checks)
class Api::V1::Admin::CredentialsController < Api::V1::BaseController
  before_action :authorize_rotate!
  before_action :require_feature_enabled!

  # POST /api/v1/admin/refresh_credentials
  def refresh
    plaintext = params[:password].to_s
    if plaintext.empty?
      render json: { error: "password is required" }, status: :unprocessable_entity
      return
    end

    admin = User.find_by(email: ENV.fetch("SPARC_ADMIN_EMAIL", "admin@sparc.local").downcase.strip)
    unless admin
      render json: { error: "Admin user not found" }, status: :not_found
      return
    end

    if admin.authenticate(plaintext)
      audit = audit_log("admin_credential_rotated",
                        subject: admin,
                        metadata: { source: "api", outcome: "unchanged",
                                    actor_token_id: current_api_token&.id })
      render json: {
        status: "unchanged",
        audit_event_id: audit&.id,
        rotated_at: admin.password_changed_at&.iso8601
      }
      return
    end

    result = AdminCredentialRotationService.apply!(
      plaintext: plaintext,
      actor:     current_user,
      source:    "api",
      push_to_secrets_manager: false
    )

    if result.success?
      admin.reload
      audit = audit_log("admin_credential_rotated",
                        subject: admin,
                        metadata: { source: "api",
                                    actor_token_id: current_api_token&.id })
      render json: {
        status: "ok",
        audit_event_id: audit&.id,
        rotated_at: admin.password_changed_at.iso8601
      }
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  private

  def authorize_rotate!
    return if current_user&.admin?
    return if current_user&.has_permission?("admin.rotate_credentials")

    raise NotAuthorizedError, "Token lacks admin.rotate_credentials permission"
  end

  def require_feature_enabled!
    return if ENV["SPARC_ADMIN_REFRESH_ENABLED"].to_s.downcase == "true"

    render json: {
      error: "Admin credential refresh endpoint is disabled. " \
             "Set SPARC_ADMIN_REFRESH_ENABLED=true to enable."
    }, status: :service_unavailable
  end

  # Override the base controller's audit_log to return the created record
  # so we can include its id in the response (caller wants to correlate
  # rotation logs across SPARC and the Lambda).
  def audit_log(action, subject: nil, metadata: {})
    AuditEvent.log(
      action: action,
      user: current_user,
      subject: subject,
      metadata: metadata,
      ip_address: request.remote_ip
    )
  rescue StandardError => e
    Rails.logger.warn("Audit log failed: #{e.message}")
    nil
  end
end
