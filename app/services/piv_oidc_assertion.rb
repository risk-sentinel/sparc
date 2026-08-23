# frozen_string_literal: true

# #822 — decide whether an OIDC token proves a smart card was used at the IdP.
#
# SPARC's `piv` auth method has always meant "a gateway terminated mTLS and
# forwarded the client certificate". That path stays. This adds a second way to
# satisfy the same requirement: an OIDC token whose `acr` or `amr` claim shows
# the IdP itself performed certificate-based authentication (Okta Smart Card,
# Entra CBA).
#
# ── Why an operator would want the IdP to do it ───────────────────────────
#
# Gateway mTLS on a shared :443 listener prompts EVERY user for a client
# certificate, because the CertificateRequest happens at the TLS layer before
# HTTP exists and cannot be scoped to a path. It also trusts an issuer-DN
# filter, which cannot tell a hardware-bound PIV credential from an exportable
# soft certificate issued by the same CA. An IdP doing CBA enforces chain
# validation, revocation and hardware assurance, and says so in the token.
#
# ── Opt-in, and inert by default ──────────────────────────────────────────
#
# With neither variable set this returns false for everything, so an existing
# deployment behaves exactly as before: `piv` continues to mean the cert header
# and nothing else. **An empty allowlist must never mean "accept anything"** —
# that is the failure mode where a configuration mistake silently downgrades an
# authentication requirement, and it is the single most important property here.
#
# NIST 800-53: IA-2(1)/(2) (MFA), IA-2(12) (PIV credential acceptance),
# IA-5(2) (PKI-based authentication), IA-8(1) (federated PIV).
class PivOidcAssertion
  def initialize(auth)
    @auth = auth
  end

  # True only when the operator named a value AND the token carries it.
  def satisfied? = matched_acr.present? || matched_amr.any?

  # What matched, for the audit record. An assessor asking "why did SPARC accept
  # this as PIV?" gets the claim and the value, not just a boolean.
  def evidence
    return nil unless satisfied?

    { acr: matched_acr, amr: matched_amr }.compact_blank
  end

  private

  def matched_acr
    accepted = SparcConfig.piv_oidc_acr_values
    return nil if accepted.empty?

    value = claim("acr")
    return nil if value.blank?

    accepted.include?(normalize(value)) ? value : nil
  end

  def matched_amr
    accepted = SparcConfig.piv_oidc_amr_values
    return [] if accepted.empty?

    # `amr` is a LIST of methods used. Any one of them matching is enough,
    # because the claim describes what the IdP did and the operator has said
    # which of those they consider sufficient.
    Array(claim("amr")).select { |value| accepted.include?(normalize(value)) }
  end

  # Read from the provider's raw claims. OmniAuth's `info` is a normalised
  # subset that does not carry acr/amr, so reading them from it would silently
  # find nothing and quietly refuse every PIV login.
  def claim(name)
    extra = @auth.respond_to?(:extra) ? @auth.extra : nil
    raw = extra.respond_to?(:raw_info) ? extra.raw_info : nil
    return nil if raw.nil?

    hash = raw.respond_to?(:to_h) ? raw.to_h.transform_keys(&:to_s) : {}
    hash[name]
  end

  # acr values are URIs and amr values are short tokens; both are compared
  # case-insensitively and trimmed, because they are typed into an IdP console
  # and into SPARC's configuration by different people.
  def normalize(value) = value.to_s.strip.downcase
end
