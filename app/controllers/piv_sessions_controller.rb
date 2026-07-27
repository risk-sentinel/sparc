# frozen_string_literal: true

# PIV / CAC smart-card sign-in (#779, Track B). The user's certificate + card PIN
# is a complete, MFA-grade authentication. The mTLS handshake, DoD PKI validation,
# and revocation happen at the proxy/ALB (sparc-iac, issue risk-sentinel/sparc-iac#559);
# SPARC consumes the *validated* cert the proxy forwards, maps it to a user, and
# establishes a session.
#
# Trust boundary (critical): SPARC trusts the forwarded headers ONLY because the
# proxy sets the verify-result header and strips any client-supplied copies, and
# the app is reachable only through the proxy. This controller fails closed unless
# the proxy explicitly signals a successful verification.
#
# NIST 800-53: IA-2 / IA-2(12) (PIV acceptance), IA-5(2) (PKI-based auth,
# validated upstream), AU-2 (login audited).
class PivSessionsController < ApplicationController
  skip_before_action :require_authentication, raise: false
  skip_before_action :check_password_reset, raise: false
  before_action :require_piv

  # GET /auth/piv
  def create
    unless proxy_verified?
      return failure(nil, nil, "Your smart card could not be verified by the gateway.")
    end

    # #824 — these two failures used to share one message ("No smart card
    # certificate was presented"), so an operator reading the audit log could
    # not tell "the gateway forwarded nothing" from "the gateway forwarded
    # something we could not read". They are completely different faults with
    # completely different fixes, and conflating them cost days of diagnosis on
    # a card that was working the whole time. Keep them apart.
    raw_cert = raw_client_cert_header
    if raw_cert.blank?
      return failure(nil, nil, "No smart card certificate was presented.")
    end

    identity = PivAuthService.parse(raw_cert)
    if identity.nil?
      return failure(nil, nil, "Your smart card certificate could not be read.")
    end

    # #804 — optional org issuer/policy acceptance filter (defense-in-depth on top
    # of the gateway's CA validation). No-op unless SPARC_PIV_ACCEPTED_* are set.
    unless PivAuthService.cert_accepted?(client_cert_pem)
      return failure(nil, identity, "This smart card certificate is not from an accepted issuer.")
    end

    user = PivAuthService.find_user(identity)
    return failure(user, identity, "This smart card is not linked to an active SPARC account.") if user.nil?

    start_session(user, ip_address: request.remote_ip, provider: "piv")
    AuditEvent.log(
      user: user, action: "login_success", provider: "piv",
      ip_address: request.remote_ip, user_agent: request.user_agent,
      metadata: { auth_method: "piv", edipi: identity.edipi }
    )
    redirect_to(session.delete(:return_to) || root_path, success: "Signed in with your smart card.")
  end

  private

  def require_piv
    head :not_found unless SparcConfig.enable_piv?
  end

  # Fail closed unless the proxy attests a successful mTLS verification.
  def proxy_verified?
    request.headers[SparcConfig.piv_verify_header].to_s.strip.casecmp?(SparcConfig.piv_verify_success)
  end

  # The raw forwarded header, exactly as the proxy set it. Decoding and PEM
  # reassembly belong to PivAuthService.normalize_pem, which knows every shape
  # the different proxies emit.
  def raw_client_cert_header
    request.headers[SparcConfig.piv_cert_header].to_s
  end

  def client_cert_pem
    PivAuthService.normalize_pem(raw_client_cert_header)
  end

  # Shape-only facts about what the proxy forwarded, so a failed login is
  # diagnosable from the audit log without a redeploy.
  #
  # NEVER include the certificate itself, or any part of it. The audit log is
  # widely readable and a PIV cert carries the holder's identity; "just the
  # first few characters" is how that rule erodes. Length and shape are enough
  # to tell absent from truncated from mangled, which is the whole question.
  def cert_diagnostics
    raw = raw_client_cert_header
    {
      cert_header: SparcConfig.piv_cert_header,
      cert_bytes: raw.bytesize,
      cert_has_pem_markers: raw.include?("BEGIN CERTIFICATE"),
      cert_url_encoded: raw.include?("%"),
      cert_normalized: PivAuthService.normalize_pem(raw).present?
    }
  end

  def failure(user, identity, message)
    AuditEvent.log(
      user: user, action: "login_failure", provider: "piv",
      ip_address: request.remote_ip, user_agent: request.user_agent,
      metadata: { auth_method: "piv", reason: message, edipi: identity&.edipi }
        .merge(cert_diagnostics)
    )
    redirect_to login_path, error: message
  end
end
