# frozen_string_literal: true

require "rails_helper"

# PIV / CAC sign-in app side (#779, Track B). The mTLS + DoD-PKI validation is the
# proxy's job (sparc-iac); here we test SPARC consuming the FORWARDED validated
# cert. Header injection stands in for the proxy — both directions per #783:
# a verified cert linked to a user signs in; an unverified/spoofed header, an
# unprovisioned cert, and a disabled flag are all rejected fail-closed.
RSpec.describe "PivSessions", type: :request do
  # A DoD-style client cert: CN carries the 10-digit EDIPI, SAN carries the email.
  def dod_cert(cn: "DOE.JOHN.Q.1234567890", email: "john.doe@mil")
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.add_extension(ef.create_extension("subjectAltName", "email:#{email}"))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end

  def piv_headers(pem, verified: true)
    {
      SparcConfig.piv_verify_header => (verified ? SparcConfig.piv_verify_success : "NONE"),
      SparcConfig.piv_cert_header => pem
    }
  end

  before { allow(SparcConfig).to receive(:enable_piv?).and_return(true) }

  context "with a verified cert linked to a user" do
    let!(:user) { create(:user, email: "john.doe@mil") }

    it "signs the user in and audits it (matched by email SAN)" do
      expect { get piv_session_path, headers: piv_headers(dod_cert) }
        .to change { AuditEvent.where(action: "login_success", provider: "piv").count }.by(1)
      expect(response).to redirect_to(root_path)
    end

    it "matches a pre-provisioned PIV identity by EDIPI" do
      other = create(:user, email: "someone-else@example.test")
      other.identities.create!(provider: "piv", uid: "1234567890")
      get piv_session_path, headers: piv_headers(dod_cert(email: "no-such-email@mil"))
      # EDIPI match wins even though the email doesn't resolve.
      expect(response).to redirect_to(root_path)
    end
  end

  context "fail-closed" do
    let!(:user) { create(:user, email: "john.doe@mil") }

    it "rejects when the gateway did not verify the cert (anti-spoof)" do
      expect { get piv_session_path, headers: piv_headers(dod_cert, verified: false) }
        .to change { AuditEvent.where(action: "login_failure", provider: "piv").count }.by(1)
      expect(response).to redirect_to(login_path)
    end

    it "rejects a cert with no matching account" do
      get piv_session_path, headers: piv_headers(dod_cert(cn: "NOBODY.9999999999", email: "ghost@mil"))
      expect(response).to redirect_to(login_path)
    end
  end

  it "404s when PIV is disabled" do
    allow(SparcConfig).to receive(:enable_piv?).and_return(false)
    get piv_session_path, headers: piv_headers(dod_cert)
    expect(response).to have_http_status(:not_found)
  end

  describe PivAuthService do
    it "extracts EDIPI and email from a DoD cert" do
      identity = described_class.parse(dod_cert)
      expect(identity.edipi).to eq("1234567890")
      expect(identity.email).to eq("john.doe@mil")
    end

    it "returns nil for junk input" do
      expect(described_class.parse("not a cert")).to be_nil
    end
  end
end
