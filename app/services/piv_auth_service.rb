# frozen_string_literal: true

# Parse a PIV / CAC client certificate that the mTLS proxy has already validated,
# and resolve it to a SPARC user (#779, Track B; identity mapping made
# configurable and UPN-aware in #790).
#
# The proxy (ALB/nginx, configured in sparc-iac, risk-sentinel/sparc-iac#559)
# terminates mutual TLS, validates the cert against the trusted PKI chain, checks
# revocation, and forwards the verified PEM. This service does NOT establish
# trust — it extracts identity from an already-trusted cert.
#
# ── Identity mapping ────────────────────────────────────────────────────────
# The PRIMARY identifier comes from the field named by SPARC_PIV_IDENTITY_SOURCE
# (default edipi_cn — DoD behaviour), extracted and validated per
# SPARC_PIV_UID_PATTERN, and matched against a provisioned Identity
# (provider "piv", uid = that value). If no PIV Identity matches AND
# SPARC_PIV_ALLOW_EMAIL_MATCH is true (the default), it falls back to matching
# the cert's rfc822Name against User.email.
#
#   edipi_cn   — DoD EDIPI: the last dotted segment of the Subject CN
#                ("LAST.FIRST.MI.1234567890"), which MUST be exactly 10 digits.
#   upn        — the PIV UPN carried in the SAN otherName, OID
#                1.3.6.1.4.1.311.20.2.3 (OpenSSL renders this as
#                "othername:<unsupported>", so it is decoded from the raw ASN.1).
#   email      — the rfc822Name in the SAN.
#   subject_cn — the whole Subject CN string.
#
# There is NO auto-creation: a cert with no matching account is rejected.
#
# ── Trust boundary (critical) ───────────────────────────────────────────────
# The email fallback authenticates ANY proxy-trusted cert bearing a matching
# address, so it is only as strong as the proxy's PKI anchor scoping
# (sparc-iac#559). Deployments that cannot accept that set
# SPARC_PIV_ALLOW_EMAIL_MATCH=false to require an explicit EDIPI/UPN mapping.
#
# NIST 800-53: IA-2 / IA-2(12), IA-5(2), AC-3 / AC-6, AU-2 / AU-3.
class PivAuthService
  # `uid` is the primary identifier from the configured source; `email` is the
  # rfc822Name used for the optional fallback; `subject` is retained for audit.
  Identity = Struct.new(:uid, :email, :subject, keyword_init: true) do
    # Back-compat alias: the audit log and controller still read `edipi`. With
    # the default edipi_cn source this IS the EDIPI; with another source it is
    # whatever that source yields, which is the right thing to audit.
    def edipi = uid
  end

  UPN_OID = "1.3.6.1.4.1.311.20.2.3"

  class << self
    # Parse a PEM string into an Identity, or nil if it isn't a usable cert.
    def parse(cert_pem)
      return nil if cert_pem.blank?

      cert = OpenSSL::X509::Certificate.new(cert_pem)
      Identity.new(
        uid:     extract_uid(cert),
        email:   extract_email(cert),
        subject: cert.subject.to_s
      )
    rescue OpenSSL::X509::CertificateError, OpenSSL::OpenSSLError
      nil
    end

    # Resolve a parsed Identity to an active SPARC user, or nil.
    def find_user(identity)
      return nil if identity.nil?

      user = user_by_piv(identity.uid)
      user ||= user_by_email(identity.email) if SparcConfig.piv_allow_email_match?
      user if user&.active?
    end

    private

    # ── Primary identifier, per SPARC_PIV_IDENTITY_SOURCE ────────────────────
    def extract_uid(cert)
      raw = case SparcConfig.piv_identity_source
      when "upn"        then extract_upn(cert)
      when "email"      then extract_email(cert)
      when "subject_cn" then subject_cn(cert)
      else                   subject_cn(cert) # edipi_cn: pattern applied below
      end
      return nil if raw.blank?

      apply_uid_rule(raw)
    end

    # An operator-supplied pattern wins for every source. Otherwise edipi_cn gets
    # the DoD default (last dotted CN segment, exactly 10 digits); other sources
    # use the raw value as-is.
    def apply_uid_rule(raw)
      if (pattern = SparcConfig.piv_uid_pattern)
        Regexp.new(pattern).match(raw)&.then { |m| m[1] || m[0] }
      elsif SparcConfig.piv_identity_source == "edipi_cn"
        edipi_from_cn(raw)
      else
        raw
      end
    rescue RegexpError
      nil
    end

    # DoD CAC CN is "LAST.FIRST.MI.EDIPI"; the EDIPI is the final dotted segment
    # and must be exactly 10 digits. Taking the segment (not "the last 10-digit
    # run anywhere in the string") avoids capturing digits from a name or a
    # longer number. #790.
    def edipi_from_cn(cn)
      last = cn.to_s.split(".").last
      last if last&.match?(/\A\d{10}\z/)
    end

    def subject_cn(cert)
      cert.subject.to_a.find { |name, _, _| name == "CN" }&.at(1)
    end

    # ── SAN fields ──────────────────────────────────────────────────────────
    # rfc822Name entries in the SAN, e.g. "email:john.doe@mail.mil".
    def extract_email(cert)
      san = cert.extensions.find { |e| e.oid == "subjectAltName" }
      return nil unless san

      san.value.split(",").map(&:strip).find { |v| v.start_with?("email:") }&.delete_prefix("email:")
    end

    # The PIV UPN lives in a SAN otherName (OID 1.3.6.1.4.1.311.20.2.3). OpenSSL
    # renders it as "othername:<unsupported>", so it is decoded from the raw
    # ASN.1: GeneralNames → the [0] otherName → its type-id OID → the EXPLICIT
    # [0] UTF8String value.
    def extract_upn(cert)
      ext = cert.extensions.find { |e| e.oid == "subjectAltName" }
      return nil unless ext

      octet = OpenSSL::ASN1.decode(ext.to_der).value.find { |v| v.is_a?(OpenSSL::ASN1::OctetString) }
      return nil unless octet

      OpenSSL::ASN1.decode(octet.value).value.each do |gn|
        next unless gn.respond_to?(:tag) && gn.tag == 0 && gn.tag_class == :CONTEXT_SPECIFIC

        parts = gn.value
        parts = parts.first.value if parts.is_a?(Array) && parts.first.is_a?(OpenSSL::ASN1::Sequence)
        parts = Array(parts)
        oid = parts.find { |x| x.is_a?(OpenSSL::ASN1::ObjectId) }
        next unless oid&.oid == UPN_OID

        wrapper = parts.find { |x| x.respond_to?(:tag) && x.tag == 0 && !x.is_a?(OpenSSL::ASN1::ObjectId) }
        inner = wrapper&.value
        inner = inner.first if inner.is_a?(Array)
        return inner.respond_to?(:value) ? inner.value.to_s.presence : inner.to_s.presence
      end
      nil
    rescue OpenSSL::ASN1::ASN1Error
      nil
    end

    def user_by_piv(uid)
      return nil if uid.blank?

      ::Identity.find_by(provider: "piv", uid: uid)&.user
    end

    def user_by_email(email)
      return nil if email.blank?

      User.find_by("LOWER(email) = ?", email.downcase.strip)
    end
  end
end
