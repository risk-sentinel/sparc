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
  def build_cert(cn:, san: nil)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.serial = 1
    cert.version = 2
    cert.not_before = Time.now - 3600
    cert.not_after  = Time.now + 3600
    if san
      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = cert
      ef.issuer_certificate = cert
      cert.add_extension(ef.create_extension("subjectAltName", san))
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
end
