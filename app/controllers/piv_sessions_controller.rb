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

    identity = PivAuthService.parse(client_cert_pem)
    return failure(nil, identity, "No smart card certificate was presented.") if identity.nil?

    user = PivAuthService.find_user(identity)
    return failure(user, identity, "This smart card is not linked to an active SPARC account.") if user.nil?

    start_session(user, ip_address: request.remote_ip)
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

  # The forwarded PEM may be URL-encoded (nginx $ssl_client_escaped_cert, ALB).
  def client_cert_pem
    raw = request.headers[SparcConfig.piv_cert_header].to_s
    raw.include?("%") ? CGI.unescape(raw) : raw
  end

  def failure(user, identity, message)
    AuditEvent.log(
      user: user, action: "login_failure", provider: "piv",
      ip_address: request.remote_ip, user_agent: request.user_agent,
      metadata: { auth_method: "piv", reason: message, edipi: identity&.edipi }
    )
    redirect_to login_path, error: message
  end
end
