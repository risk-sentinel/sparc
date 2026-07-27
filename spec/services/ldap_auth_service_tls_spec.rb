# frozen_string_literal: true

require "rails_helper"

# Both-directions TLS verification for the LDAP directory connection (#783).
#
# `spec/services/ldap_auth_service_spec.rb` captures the kwargs handed to
# Net::LDAP.new and asserts `verify_mode: VERIFY_PEER` is among them. That is a
# configuration assertion — it cannot distinguish a stack that verifies from one
# that merely says it does. These examples point LdapAuthService at a REAL
# LDAPS listener and assert the outcome of a REAL handshake in both directions.
#
# LDAP is the highest-value MITM target in SPARC: a bind carries the user's
# cleartext password. An unauthenticated server certificate means those
# credentials go to whoever is on the path (#773).
#
# NIST SC-8, IA-2, IA-5.
RSpec.describe LdapAuthService, "TLS verification (both directions)" do
  # Point SparcConfig at the in-test directory. Only `host`/`port` change per
  # example; trust posture is varied through ldap_tls_verify?/ldap_ca_file so
  # each example differs from its counterpart in exactly one variable.
  def configure_ldap(server, encryption: "simple_tls", verify: true, ca_file: nil)
    allow(SparcConfig).to receive_messages(
      enable_ldap?: true,
      ldap_host: server[:host],
      ldap_port: server[:port],
      ldap_encryption: encryption,
      ldap_bind_dn: "cn=svc,dc=example,dc=com",
      ldap_bind_password: "svc-pass",
      ldap_base: "ou=people,dc=example,dc=com",
      ldap_attribute: "uid",
      ldap_ca_file: ca_file,
      ldap_tls_verify?: verify
    )
  end

  # LdapAuthService rescues Net::LDAP::Error and logs it, so the TLS outcome
  # surfaces through the log rather than as a raised exception. Capture it.
  def capture_ldap_errors
    messages = []
    allow(Rails.logger).to receive(:error) { |msg| messages << msg.to_s }
    yield
    messages.join("\n")
  end

  describe "an untrusted directory certificate" do
    it "REJECTS the bind — authenticate returns nil and never reaches the directory" do
      TlsTestServer.ldaps(ca: TlsTestServer.rogue_ca) do |server|
        configure_ldap(server)

        result = nil
        log = capture_ldap_errors { result = described_class.authenticate("jdoe", "s3cret") }

        expect(result).to be_nil
        expect(log).to match(/certificate verify failed/i)
      end
    end

    it "REJECTS the bind for start_tls as well as simple_tls" do
      TlsTestServer.ldaps(ca: TlsTestServer.rogue_ca, starttls: true) do |server|
        configure_ldap(server, encryption: "start_tls")

        result = nil
        log = capture_ldap_errors { result = described_class.authenticate("jdoe", "s3cret") }

        expect(result).to be_nil
        # Must fail on the CERTIFICATE, not merely fail. An implicit-TLS
        # listener would reject a start_tls client for protocol reasons and
        # this example would pass without proving anything about trust.
        expect(log).to match(/certificate verify failed/i)
      end
    end

    # TDD teeth / control: the SAME rogue directory authenticates the user the
    # moment verification is opted out. So the rejections above are caused by
    # certificate verification, not by an unreachable or misbehaving listener —
    # and this doubles as the documented behavior of the opt-out.
    it "is otherwise reachable — the same server authenticates when verification is opted out" do
      TlsTestServer.ldaps(ca: TlsTestServer.rogue_ca) do |server|
        configure_ldap(server, verify: false)
        allow(Rails.logger).to receive(:warn)

        expect(described_class.authenticate("jdoe", "s3cret")).to include(
          dn: "uid=jdoe,ou=people,dc=example,dc=com",
          email: "jdoe@example.com"
        )
      end
    end
  end

  describe "a trusted directory certificate" do
    it "ACCEPTS the bind and returns the user when SPARC_LDAP_CA_FILE supplies the CA" do
      TlsTestServer.ldaps(ca: TlsTestServer.trusted_ca) do |server|
        configure_ldap(server, ca_file: server[:ca_file])

        expect(described_class.authenticate("jdoe", "s3cret")).to include(
          dn: "uid=jdoe,ou=people,dc=example,dc=com",
          email: "jdoe@example.com",
          username: "jdoe"
        )
      end
    end

    it "ACCEPTS start_tls against the same trusted directory" do
      TlsTestServer.ldaps(ca: TlsTestServer.trusted_ca, starttls: true) do |server|
        configure_ldap(server, encryption: "start_tls", ca_file: server[:ca_file])

        expect(described_class.authenticate("jdoe", "s3cret")).to be_present
      end
    end
  end

  # A chain check alone is not enough under a private PKI: an enterprise CA
  # signs certificates for MANY hosts, so any holder of one could impersonate
  # the directory if only the chain were validated. net-ldap performs
  # post_connection_check(host) whenever verify_mode is not VERIFY_NONE — this
  # pins that behavior so a future tls_options change cannot silently drop it.
  describe "a certificate issued for a DIFFERENT hostname" do
    it "REJECTS it even though it chains to the trusted CA" do
      TlsTestServer.ldaps(ca: TlsTestServer.trusted_ca, sans: [ "DNS:not-our-directory.example.com" ]) do |server|
        configure_ldap(server, ca_file: server[:ca_file])

        result = nil
        log = capture_ldap_errors { result = described_class.authenticate("jdoe", "s3cret") }

        expect(result).to be_nil
        expect(log).to match(/hostname mismatch/i)
      end
    end
  end

  describe "SPARC_LDAP_TLS_VERIFY=false (documented opt-out)" do
    it "logs a loud, unmissable warning whenever verification is disabled" do
      TlsTestServer.ldaps(ca: TlsTestServer.rogue_ca) do |server|
        configure_ldap(server, verify: false)
        warnings = []
        allow(Rails.logger).to receive(:warn) { |msg| warnings << msg.to_s }

        described_class.authenticate("jdoe", "s3cret")

        expect(warnings.join("\n")).to match(/verification is DISABLED/i)
        expect(warnings.join("\n")).to match(/man-in-the-middle/i)
      end
    end

    it "is opt-out ONLY — the default posture rejects the very cert it accepts" do
      TlsTestServer.ldaps(ca: TlsTestServer.rogue_ca) do |server|
        # Default posture: rejected.
        configure_ldap(server, verify: true)
        rejected = capture_ldap_errors { described_class.authenticate("jdoe", "s3cret") }
        expect(rejected).to match(/certificate verify failed/i)

        # Same server, opt-out enabled: accepted. One variable changed.
        configure_ldap(server, verify: false)
        allow(Rails.logger).to receive(:warn)
        expect(described_class.authenticate("jdoe", "s3cret")).to be_present
      end
    end
  end
end
