# frozen_string_literal: true

# Security headers middleware — sets defence-in-depth HTTP headers on every
# response.  These complement Rails' built-in CSRF, force_ssl / HSTS, and
# Content-Security-Policy protections.
#
# References:
#   NIST SP 800-53  SC-8  (Transmission Confidentiality and Integrity)
#   NIST SP 800-53  SC-28 (Protection of Information at Rest)
#   OWASP Secure Headers Project
#
# See also: config/initializers/content_security_policy.rb for CSP.

class SecurityHeadersMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # Prevent MIME-type sniffing (IE/Chrome)
    headers["x-content-type-options"] ||= "nosniff"

    # Clickjacking protection — allow framing only from same origin
    headers["x-frame-options"] ||= "SAMEORIGIN"

    # Control Referer header leakage
    headers["referrer-policy"] ||= "strict-origin-when-cross-origin"

    # Restrict powerful browser APIs the app does not use
    headers["permissions-policy"] ||= "camera=(), microphone=(), geolocation=()"

    # Block Adobe Flash / Acrobat cross-domain data loading
    headers["x-permitted-cross-domain-policies"] ||= "none"

    [ status, headers, response ]
  end
end

Rails.application.config.middleware.insert_after ActionDispatch::Static, SecurityHeadersMiddleware
