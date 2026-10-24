# frozen_string_literal: true

# #1098 — the boot-time line saying whether OIDC sign-in is on and whether an
# egress proxy applies to the issuer (config/initializers/zz_oidc_egress_posture.rb).
#
# Discovery is lazy: SPARC fetches `{issuer}/.well-known/openid-configuration`
# and the IdP's keys over outbound HTTPS when a user signs in, not at boot. So a
# deployment whose mandated egress proxy is not configured boots clean, offers
# the sign-in button, and fails only when someone presses it, which reads as an
# OIDC fault rather than a network one. This puts the two facts side by side.
#
# It makes NO network call: probing the IdP at boot would make startup depend
# on the IdP being up. A proxy URL can carry credentials, so only whether one
# applies is reported.
#
# NIST 800-53: CM-6 (configuration settings reported at start-up), AC-4.
module OidcEgressPosture
  extend self

  # nil when OIDC sign-in is off.
  def line
    issuer = SparcConfig.oidc_issuer_url
    return nil unless SparcConfig.enable_oidc? && issuer.present?

    proxy = SparcHttp.proxied?(issuer) ? "an egress proxy applies (HTTPS_PROXY)" : "no egress proxy applies"
    "[SPARC] OIDC sign-in: enabled, issuer host #{host(issuer) || '(unparseable issuer URL)'}; #{proxy}. " \
      "Discovery and JWKS are outbound HTTPS calls made at sign-in, not at boot."
  end

  def host(url)
    URI(url).host
  rescue URI::Error
    nil
  end
end
