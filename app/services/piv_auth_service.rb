# frozen_string_literal: true

# Parse a DoD PIV / CAC client certificate that the mTLS proxy has already
# validated, and resolve it to a SPARC user (#779, Track B).
#
# The proxy (ALB/nginx, configured in sparc-iac) terminates mutual TLS, validates
# the cert against the DoD PKI chain, checks revocation, and forwards the verified
# PEM. This service does NOT establish trust — it extracts identity from an
# already-trusted cert:
#
#   - EDIPI: the DoD 10-digit identifier, the last dotted segment of the Subject
#     CN ("LAST.FIRST.MI.1234567890"), or the local part of the PIV UPN.
#   - email: an rfc822Name in the Subject Alternative Name.
#
# A user is matched by a pre-provisioned PIV identity (Identity provider "piv",
# uid = EDIPI) or, failing that, by the cert's email. There is no auto-creation:
# a cert with no matching account is rejected (unprovisioned).
class PivAuthService
  Identity = Struct.new(:edipi, :email, :subject, keyword_init: true)

  class << self
    # Parse a PEM string into an Identity, or nil if it isn't a usable cert.
    def parse(cert_pem)
      return nil if cert_pem.blank?

      cert = OpenSSL::X509::Certificate.new(cert_pem)
      Identity.new(edipi: extract_edipi(cert), email: extract_email(cert), subject: cert.subject.to_s)
    rescue OpenSSL::X509::CertificateError, OpenSSL::OpenSSLError
      nil
    end

    # Resolve a parsed Identity to an active SPARC user, or nil.
    def find_user(identity)
      return nil if identity.nil?

      user = user_by_piv(identity.edipi) || user_by_email(identity.email)
      user if user&.active?
    end

    private

    def extract_edipi(cert)
      cn = cert.subject.to_a.find { |name, _, _| name == "CN" }&.at(1)
      cn&.match(/(\d{10})(?!.*\d)/)&.captures&.first
    end

    # rfc822Name entries in the SAN extension, e.g. "email:john.doe@mil".
    def extract_email(cert)
      san = cert.extensions.find { |e| e.oid == "subjectAltName" }
      return nil unless san

      san.value.split(",").map(&:strip).find { |v| v.start_with?("email:") }&.delete_prefix("email:")
    end

    def user_by_piv(edipi)
      return nil if edipi.blank?

      ::Identity.find_by(provider: "piv", uid: edipi)&.user
    end

    def user_by_email(email)
      return nil if email.blank?

      User.find_by("LOWER(email) = ?", email.downcase.strip)
    end
  end
end
