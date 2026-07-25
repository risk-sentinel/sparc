# frozen_string_literal: true

require "rails_helper"

# #790 — the PIV identity parser had no unit spec, a docs/code mismatch (UPN was
# documented but never parsed), and a CN regex that could capture the wrong
# EDIPI. These specs pin the parser directly against real certificates built for
# each shape.
RSpec.describe PivAuthService do
  # Build a self-signed cert with a given CN and SAN. Nothing here validates
  # trust — the proxy does that upstream — so a self-signed cert is a faithful
  # stand-in for "a cert the proxy already verified".
  def build_cert(cn:, san: nil, issuer_cn: nil, policy_oid: nil)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = issuer_cn ? OpenSSL::X509::Name.parse("/CN=#{issuer_cn}") : cert.subject
    cert.public_key = key.public_key
    cert.serial = 1
    cert.version = 2
    cert.not_before = Time.now - 3600
    cert.not_after  = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.add_extension(ef.create_extension("subjectAltName", san)) if san
    if policy_oid
      # Build certificatePolicies via raw ASN.1 — create_extension won't accept an
      # arbitrary policy OID. SEQUENCE OF PolicyInformation{ policyIdentifier }.
      policies = OpenSSL::ASN1::Sequence.new([ OpenSSL::ASN1::Sequence.new([ OpenSSL::ASN1::ObjectId.new(policy_oid) ]) ])
      cert.add_extension(OpenSSL::X509::Extension.new("certificatePolicies", policies.to_der, false))
    end
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end

  def with_env(vars)
    saved = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe ".parse — default source (edipi_cn)" do
    it "extracts the EDIPI from a DoD-shaped CN" do
      id = described_class.parse(build_cert(cn: "DOE.JOHN.Q.1234567890"))
      expect(id.uid).to eq("1234567890")
      expect(id.edipi).to eq("1234567890") # back-compat alias
    end

    it "takes the DOTTED SEGMENT, not any 10-digit run in the string" do
      # A CN carrying a longer number before the EDIPI must not mis-capture.
      # The old regex `(\d{10})(?!.*\d)` would have grabbed the wrong ten digits.
      id = described_class.parse(build_cert(cn: "AGENCY99999999999999.DOE.JOHN.1234567890"))
      expect(id.uid).to eq("1234567890")
    end

    it "yields nil when the final CN segment is not exactly 10 digits" do
      expect(described_class.parse(build_cert(cn: "DOE.JOHN.Q.12345")).uid).to be_nil
      expect(described_class.parse(build_cert(cn: "Plain Common Name")).uid).to be_nil
    end

    it "extracts the rfc822Name into email for the fallback" do
      id = described_class.parse(build_cert(cn: "DOE.JOHN.Q.1234567890",
                                            san: "email:john.doe@mail.mil"))
      expect(id.email).to eq("john.doe@mail.mil")
    end
  end

  describe ".parse — UPN source (the previously-missing capability)" do
    let(:cert) do
      build_cert(cn: "DOE.JOHN.Q.1234567890",
                 san: "email:john.doe@mail.mil,otherName:#{described_class::UPN_OID};UTF8:1234567890@mil")
    end

    it "decodes the UPN from the SAN otherName" do
      with_env("SPARC_PIV_IDENTITY_SOURCE" => "upn") do
        expect(described_class.parse(cert).uid).to eq("1234567890@mil")
      end
    end

    it "is NOT used under the default source (proves the source selector works)" do
      # Same cert, default edipi_cn source → uid is the EDIPI, not the UPN.
      expect(described_class.parse(cert).uid).to eq("1234567890")
    end

    it "yields nil uid when a upn-source cert carries no otherName" do
      with_env("SPARC_PIV_IDENTITY_SOURCE" => "upn") do
        expect(described_class.parse(build_cert(cn: "DOE.JOHN.Q.1234567890")).uid).to be_nil
      end
    end
  end

  describe ".parse — email and subject_cn sources" do
    it "uses the rfc822Name as the primary identifier under email source" do
      with_env("SPARC_PIV_IDENTITY_SOURCE" => "email") do
        id = described_class.parse(build_cert(cn: "anything", san: "email:jane@corp.example"))
        expect(id.uid).to eq("jane@corp.example")
      end
    end

    it "uses the whole CN under subject_cn source" do
      with_env("SPARC_PIV_IDENTITY_SOURCE" => "subject_cn") do
        expect(described_class.parse(build_cert(cn: "corp-user-42")).uid).to eq("corp-user-42")
      end
    end
  end

  describe ".parse — SPARC_PIV_UID_PATTERN (non-DoD identifiers)" do
    it "extracts a custom uid shape from the source with a capture group" do
      with_env("SPARC_PIV_IDENTITY_SOURCE" => "subject_cn",
               "SPARC_PIV_UID_PATTERN" => "employee-(\\d+)") do
        expect(described_class.parse(build_cert(cn: "employee-8842")).uid).to eq("8842")
      end
    end

    it "falls back to the whole match when the pattern has no capture group" do
      with_env("SPARC_PIV_IDENTITY_SOURCE" => "subject_cn",
               "SPARC_PIV_UID_PATTERN" => "[A-Z]{3}\\d{4}") do
        expect(described_class.parse(build_cert(cn: "user ABC1234 x")).uid).to eq("ABC1234")
      end
    end
  end

  describe ".parse — resilience" do
    it "returns nil on a blank or malformed PEM rather than raising" do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse("-----BEGIN CERTIFICATE-----\nnope\n-----END CERTIFICATE-----")).to be_nil
    end
  end

  describe ".find_user" do
    let(:user) { create(:user) }

    it "matches a provisioned PIV Identity by uid" do
      Identity.create!(user: user, provider: "piv", uid: "1234567890")
      id = PivAuthService::Identity.new(uid: "1234567890", email: nil, subject: "x")
      expect(described_class.find_user(id)).to eq(user)
    end

    it "falls back to email when no PIV Identity matches (default)" do
      id = PivAuthService::Identity.new(uid: "0000000000", email: user.email, subject: "x")
      expect(described_class.find_user(id)).to eq(user)
    end

    it "refuses the email fallback when SPARC_PIV_ALLOW_EMAIL_MATCH=false" do
      with_env("SPARC_PIV_ALLOW_EMAIL_MATCH" => "false") do
        id = PivAuthService::Identity.new(uid: "0000000000", email: user.email, subject: "x")
        expect(described_class.find_user(id)).to be_nil
      end
    end

    it "still honours a PIV Identity match when email matching is disabled" do
      Identity.create!(user: user, provider: "piv", uid: "1234567890")
      with_env("SPARC_PIV_ALLOW_EMAIL_MATCH" => "false") do
        id = PivAuthService::Identity.new(uid: "1234567890", email: nil, subject: "x")
        expect(described_class.find_user(id)).to eq(user)
      end
    end

    it "rejects an inactive user" do
      user.update!(status: "deactivated")
      Identity.create!(user: user, provider: "piv", uid: "1234567890")
      id = PivAuthService::Identity.new(uid: "1234567890", email: user.email, subject: "x")
      expect(described_class.find_user(id)).to be_nil
    end

    it "rejects an unprovisioned identity (no PIV Identity, no matching email)" do
      id = PivAuthService::Identity.new(uid: "9999999999", email: "nobody@nowhere.test", subject: "x")
      expect(described_class.find_user(id)).to be_nil
    end
  end

  describe ".cert_accepted? — #804 issuer/policy filter (defense-in-depth)" do
    let(:pol) { "1.3.6.1.4.1.99999.1.1" }

    it "accepts any cert when no filter is configured (default, no behavior change)" do
      expect(described_class.cert_accepted?(build_cert(cn: "USER.1234567890"))).to be(true)
    end

    it "accepts a cert whose issuer DN matches an accepted issuer (substring)" do
      pem = build_cert(cn: "USER.1234567890", issuer_cn: "ACME Corp PIV CA")
      with_env("SPARC_PIV_ACCEPTED_ISSUERS" => "ACME Corp PIV CA") do
        expect(described_class.cert_accepted?(pem)).to be(true)
      end
    end

    it "rejects a cert from an issuer not on the allowlist" do
      pem = build_cert(cn: "USER.1234567890", issuer_cn: "Rogue CA")
      with_env("SPARC_PIV_ACCEPTED_ISSUERS" => "ACME Corp PIV CA") do
        expect(described_class.cert_accepted?(pem)).to be(false)
      end
    end

    it "accepts a cert carrying an accepted certificate-policy OID" do
      pem = build_cert(cn: "USER.1", policy_oid: pol)
      with_env("SPARC_PIV_ACCEPTED_POLICY_OIDS" => pol) do
        expect(described_class.cert_accepted?(pem)).to be(true)
      end
    end

    it "rejects a cert missing the accepted policy OID" do
      pem = build_cert(cn: "USER.1", policy_oid: "1.3.6.1.4.1.99999.9.9")
      with_env("SPARC_PIV_ACCEPTED_POLICY_OIDS" => pol) do
        expect(described_class.cert_accepted?(pem)).to be(false)
      end
    end

    it "requires BOTH when issuer and policy are configured" do
      good = build_cert(cn: "USER.1", issuer_cn: "ACME PIV CA", policy_oid: pol)
      bad  = build_cert(cn: "USER.1", issuer_cn: "ACME PIV CA", policy_oid: "1.3.6.1.4.1.99999.9.9")
      with_env("SPARC_PIV_ACCEPTED_ISSUERS" => "ACME PIV CA", "SPARC_PIV_ACCEPTED_POLICY_OIDS" => pol) do
        expect(described_class.cert_accepted?(good)).to be(true)
        expect(described_class.cert_accepted?(bad)).to be(false)
      end
    end

    it "fails closed on a blank or garbage cert" do
      with_env("SPARC_PIV_ACCEPTED_ISSUERS" => "ACME PIV CA") do
        expect(described_class.cert_accepted?("")).to be(false)
        expect(described_class.cert_accepted?("not a certificate")).to be(false)
      end
    end
  end
end
