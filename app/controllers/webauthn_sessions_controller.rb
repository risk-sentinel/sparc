# frozen_string_literal: true

# Passwordless FIDO2/WebAuthn sign-in (#779). A security key + PIN is a complete,
# MFA-grade authentication on its own — possession of the token plus user
# verification (PIN/biometric) — with no password and no LDAP in the loop. The
# assertion resolves to a stored credential -> user, verifies against the stored
# public key, and promotes to a full session via start_session.
#
# Two resolution modes:
#   - usernameless (discoverable credential): the token carries the user handle;
#     the options carry an empty allow-list.
#   - email-first fallback (non-resident tokens): the entered email narrows the
#     allow-list to that user's registered credentials.
#
# NIST 800-53: IA-2 / IA-2(1)/(2) (MFA), IA-2(8) (replay-resistant via the
# signature counter), AU-2 (login_success / login_failure audited).
class WebauthnSessionsController < ApplicationController
  skip_before_action :require_authentication, raise: false
  skip_before_action :check_password_reset, raise: false
  before_action :require_fido2

  # POST /session/webauthn/options
  def options
    options = WebAuthn::Credential.options_for_get(
      allow: allow_credentials_for(params[:email]),
      user_verification: "required"
    )
    session[:webauthn_authentication_challenge] = options.challenge
    render json: options
  end

  # POST /session/webauthn
  def create
    challenge = session.delete(:webauthn_authentication_challenge)
    return unauthorized("No sign-in in progress. Please start again.") if challenge.blank?

    assertion = WebAuthn::Credential.from_get(credential_param)
    credential = WebauthnCredential.find_by(external_id: assertion.id)
    return failure(nil, "That security key is not recognized.") if credential.nil?

    assertion.verify(
      challenge,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      user_verification: true
    )

    # Defense in depth: a discoverable credential returns the user handle it was
    # registered with — it must match the user we resolved from the credential id.
    if assertion.user_handle.present? && assertion.user_handle != credential.user.webauthn_id
      return failure(credential.user, "Security key identity mismatch.")
    end

    user = credential.user
    return failure(user, "Your account is not active. Contact an administrator.") unless user.active?

    credential.record_use!(assertion.sign_count)
    start_session(user, ip_address: request.remote_ip)
    AuditEvent.log(
      user: user, action: "login_success", provider: "webauthn",
      ip_address: request.remote_ip, user_agent: request.user_agent,
      metadata: { auth_method: "webauthn" }
    )

    render json: { redirect_to: (session.delete(:return_to) || root_path) }
  rescue WebAuthn::Error => e
    failure(nil, "Your security key could not be verified. #{e.message}")
  end

  private

  def require_fido2
    head :not_found unless SparcConfig.fido2_enabled?
  end

  # The WebAuthn assertion JSON from the browser. Permit its exact structure
  # (verified cryptographically by #verify, not mass-assigned).
  def credential_param
    params.require(:credential).permit(
      :id, :rawId, :type, :authenticatorAttachment,
      response: [ :attestationObject, :clientDataJSON, :authenticatorData, :signature, :userHandle ],
      clientExtensionResults: {}
    ).to_h
  end

  # Empty for usernameless/discoverable login; the user's registered keys when an
  # email is supplied (fallback for non-resident tokens). Never leaks whether an
  # email exists — an unknown email yields an empty list, same as usernameless.
  def allow_credentials_for(email)
    return [] if email.blank?

    user = User.find_by("LOWER(email) = ?", email.to_s.downcase.strip)
    user ? user.webauthn_credentials.pluck(:external_id) : []
  end

  def failure(user, message)
    AuditEvent.log(
      user: user, action: "login_failure", provider: "webauthn",
      ip_address: request.remote_ip, user_agent: request.user_agent,
      metadata: { auth_method: "webauthn", reason: message }
    )
    unauthorized(message)
  end

  def unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end
end
