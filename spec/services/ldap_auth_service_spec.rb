# frozen_string_literal: true

require "rails_helper"

# Focus of this spec: the TLS trust posture of the LDAP connection (#773).
#
# net-ldap only authenticates the directory server's certificate when the
# encryption hash carries a NON-EMPTY tls_options with a verify_mode; omitting
# it silently falls back to VERIFY_NONE (encrypted but MITM-open). These specs
# capture the args passed to Net::LDAP.new and assert the verify_mode we send,
# which is the setting that causes OpenSSL to reject a bad server cert.
RSpec.describe LdapAuthService do
  let(:ldap_double) { instance_double(Net::LDAP) }
  # Captures the keyword args of every Net::LDAP.new call the service makes.
  let(:new_calls) { [] }

  # The DN the search step resolves the username to.
  let(:user_entry) do
    Net::LDAP::Entry.new("uid=jdoe,ou=people,dc=example,dc=com").tap do |e|
      e[:mail] = "jdoe@example.com"
      e[:cn] = "John Doe"
      e[:givenname] = "John"
      e[:sn] = "Doe"
    end
  end

  before do
    allow(SparcConfig).to receive_messages(
      enable_ldap?: true,
      ldap_host: "ldap.example.com",
      ldap_port: 636,
      ldap_encryption: "simple_tls",
      ldap_bind_dn: "cn=svc,dc=example,dc=com",
      ldap_bind_password: "svc-pass",
      ldap_base: "ou=people,dc=example,dc=com",
      ldap_attribute: "uid",
      ldap_ca_file: nil,
      ldap_tls_verify?: true
    )

    allow(Net::LDAP).to receive(:new) do |**kwargs|
      new_calls << kwargs
      ldap_double
    end
    allow(ldap_double).to receive(:bind).and_return(true)
    allow(ldap_double).to receive(:search)
      .with(base: "ou=people,dc=example,dc=com", filter: anything, size: 1)
      .and_return([ user_entry ])
  end

  # The encryption hash from the first connection (the service-account bind).
  def captured_encryption
    described_class.authenticate("jdoe", "s3cret")
    new_calls.first.fetch(:encryption)
  end

  describe "TLS certificate verification (#773)" do
    it "verifies the server certificate by default for simple_tls" do
      allow(SparcConfig).to receive(:ldap_encryption).and_return("simple_tls")
      enc = captured_encryption
      expect(enc[:method]).to eq(:simple_tls)
      expect(enc[:tls_options]).to include(verify_mode: OpenSSL::SSL::VERIFY_PEER)
    end

    it "verifies the server certificate by default for start_tls" do
      allow(SparcConfig).to receive(:ldap_encryption).and_return("start_tls")
      enc = captured_encryption
      expect(enc[:method]).to eq(:start_tls)
      expect(enc[:tls_options]).to include(verify_mode: OpenSSL::SSL::VERIFY_PEER)
    end

    it "applies verification to the user bind too, not just the service bind" do
      described_class.authenticate("jdoe", "s3cret")
      # Two connections: service-account bind + user bind. Both must verify.
      expect(new_calls.size).to eq(2)
      new_calls.each do |kwargs|
        expect(kwargs.dig(:encryption, :tls_options)).to include(
          verify_mode: OpenSSL::SSL::VERIFY_PEER
        )
      end
    end

    it "wires SPARC_LDAP_CA_FILE through to tls_options when set" do
      allow(SparcConfig).to receive(:ldap_ca_file).and_return("/etc/sparc/ldap-ca.pem")
      expect(captured_encryption[:tls_options]).to include(
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
        ca_file: "/etc/sparc/ldap-ca.pem"
      )
    end

    it "omits ca_file when SPARC_LDAP_CA_FILE is unset" do
      expect(captured_encryption[:tls_options]).not_to have_key(:ca_file)
    end

    context "when SPARC_LDAP_TLS_VERIFY=false (opt-out)" do
      before { allow(SparcConfig).to receive(:ldap_tls_verify?).and_return(false) }

      it "disables verification only when explicitly opted out" do
        expect(captured_encryption[:tls_options]).to include(
          verify_mode: OpenSSL::SSL::VERIFY_NONE
        )
      end

      it "logs a loud warning so the insecure mode cannot hide" do
        # Warns on every connection built (service bind + user bind).
        expect(Rails.logger).to receive(:warn).with(/verification is DISABLED/i).at_least(:once)
        described_class.authenticate("jdoe", "s3cret")
      end
    end

    it "does not build a TLS context for plain (cleartext) connections" do
      allow(SparcConfig).to receive(:ldap_encryption).and_return("plain")
      expect(captured_encryption).to be_nil
    end
  end

  describe "authentication flow (regression guard)" do
    it "returns the user attribute hash on a successful bind" do
      result = described_class.authenticate("jdoe", "s3cret")
      expect(result).to include(
        dn: "uid=jdoe,ou=people,dc=example,dc=com",
        email: "jdoe@example.com",
        display_name: "John Doe",
        username: "jdoe"
      )
    end

    it "returns nil when the user bind fails" do
      # Service bind succeeds, user bind fails.
      call = 0
      allow(ldap_double).to receive(:bind) { (call += 1) == 1 }
      allow(ldap_double).to receive(:get_operation_result)
        .and_return(double("PDU", message: "invalid credentials"))
      expect(described_class.authenticate("jdoe", "wrong")).to be_nil
    end

    it "returns nil when LDAP is disabled" do
      allow(SparcConfig).to receive(:enable_ldap?).and_return(false)
      expect(described_class.authenticate("jdoe", "s3cret")).to be_nil
    end

    it "returns nil for blank credentials without opening a connection" do
      expect(described_class.authenticate("", "")).to be_nil
      expect(new_calls).to be_empty
    end
  end
end
