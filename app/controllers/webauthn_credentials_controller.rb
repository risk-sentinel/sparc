# frozen_string_literal: true

# Manage a user's FIDO2 security keys (#779) — list, enroll (WebAuthn attestation
# ceremony), and revoke. Session-authenticated: the signed-in user manages their
# own keys, and the registration challenge is stashed in the session between the
# two ceremony round-trips. The browser drives navigator.credentials.create via
# the `webauthn` Stimulus controller; these endpoints are its backend.
#
# NIST 800-53: IA-2(1)/(2) MFA enrollment, IA-5 authenticator management,
# AU-2 / AU-12 (enroll and revoke are audited).
class WebauthnCredentialsController < ApplicationController
  before_action :require_fido2

  def index
    @credentials = current_user.webauthn_credentials.by_recent_use
    respond_to do |format|
      format.html
      format.json { render json: @credentials.map { |c| credential_json(c) } }
    end
  end

  # POST /webauthn_credentials/registration_options
  # Issue an attestation challenge and stash it for the follow-up create.
  def registration_options
    options = WebAuthn::Credential.options_for_create(
      user: {
        id: current_user.webauthn_handle,
        name: current_user.email,
        display_name: display_name_for(current_user)
      },
      exclude: current_user.webauthn_credentials.pluck(:external_id),
      # PIN/biometric required (MFA in one step); resident key when the token
      # supports it (usernameless login) but not required (non-resident tokens).
      authenticator_selection: { user_verification: "required", resident_key: "preferred" }
    )
    session[:webauthn_registration_challenge] = options.challenge
    render json: options
  end

  # POST /webauthn_credentials
  def create
    challenge = session.delete(:webauthn_registration_challenge)
    return render json: { error: "No enrollment in progress. Start again." }, status: :unprocessable_entity if challenge.blank?

    webauthn_credential = WebAuthn::Credential.from_create(credential_param)
    webauthn_credential.verify(challenge, user_verification: true)

    credential = current_user.webauthn_credentials.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: params[:nickname].to_s.strip.presence
    )
    audit("webauthn_key_registered", credential)
    render json: credential_json(credential), status: :created
  rescue WebAuthn::Error => e
    render json: { error: "That security key could not be verified: #{e.message}" }, status: :unprocessable_entity
  end

  # DELETE /webauthn_credentials/:id
  def destroy
    credential = current_user.webauthn_credentials.find(params[:id])
    credential.destroy!
    audit("webauthn_key_revoked", credential)
    respond_to do |format|
      format.html { redirect_to webauthn_credentials_path, notice: "Security key removed." }
      format.json { head :no_content }
    end
  end

  private

  # Graceful fallback when the feature is off: the endpoints simply don't exist.
  def require_fido2
    head :not_found unless SparcConfig.fido2_enabled?
  end

  # The WebAuthn PublicKeyCredential JSON from the browser. Permit its exact
  # structure (it is verified cryptographically by #verify, not mass-assigned).
  def credential_param
    params.require(:credential).permit(
      :id, :rawId, :type, :authenticatorAttachment,
      response: [ :attestationObject, :clientDataJSON, :authenticatorData, :signature, :userHandle ],
      clientExtensionResults: {}
    ).to_h
  end

  def display_name_for(user)
    [ user.first_name, user.last_name ].compact_blank.join(" ").presence || user.email
  end

  def credential_json(credential)
    {
      id: credential.id,
      label: credential.label,
      last_used_at: credential.last_used_at&.iso8601,
      created_at: credential.created_at.iso8601
    }
  end

  def audit(action, credential)
    AuditEvent.log(
      user: current_user, action: action, subject: credential,
      ip_address: request.remote_ip, user_agent: request.user_agent,
      metadata: { nickname: credential.nickname, external_id: credential.external_id }
    )
  end
end
