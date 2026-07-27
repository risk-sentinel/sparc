# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "shellwords"

# Both-directions TLS verification for SPARC's outbound HTTP (#783).
#
# `spec/lib/sparc_http_spec.rb` asserts that SparcHttp *passes*
# `verify_mode: VERIFY_PEER` to Net::HTTP. That is a configuration assertion:
# it would still pass on a stack that accepted an untrusted certificate anyway.
# These examples drive a REAL handshake against a REAL TLS listener and assert
# the outcome in both directions — untrusted is rejected, trusted is accepted.
#
# Every outbound client in SPARC (OIDC discovery/JWKS, federation pull, AWS Labs
# CDEF ingest, MITRE config, AWS Security Hub) routes through SparcHttp, so this
# one surface covers them all.
#
# NIST SC-8 (transmission confidentiality/integrity), SC-13, SC-23.
RSpec.describe SparcHttp, "TLS verification (both directions)" do
  # The negative and positive cases differ in exactly one variable: which CA
  # signed the leaf the server presents. Same code path, same listener plumbing,
  # same hostname. So a rejection cannot be explained by an unreachable server.
  describe "an untrusted server certificate" do
    it "is REJECTED — the handshake raises instead of returning a body" do
      TlsTestServer.https(ca: TlsTestServer.rogue_ca) do |server|
        expect {
          described_class.get(server[:uri])
        }.to raise_error(OpenSSL::SSL::SSLError, /certificate verify failed/i)
      end
    end

    it "is REJECTED for .start too, not just the .get convenience wrapper" do
      TlsTestServer.https(ca: TlsTestServer.rogue_ca) do |server|
        expect {
          described_class.start(server[:uri]) { |http| http.request(Net::HTTP::Get.new(server[:uri])) }
        }.to raise_error(OpenSSL::SSL::SSLError)
      end
    end

    # TDD teeth: proves the rejection above is caused by certificate
    # verification and nothing else. The SAME rogue server is reachable and
    # serves a 200 the moment verification is turned off. If a future change
    # dropped VERIFY_PEER, the examples above would go green while this one
    # stayed green too — and the pair would no longer disagree, which is the
    # signal to look at.
    it "is reachable and serves 200 when verification is disabled (control)" do
      TlsTestServer.https(ca: TlsTestServer.rogue_ca) do |server|
        response = described_class.start(server[:uri], verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
          http.request(Net::HTTP::Get.new(server[:uri]))
        end

        expect(response.code).to eq("200")
      end
    end
  end

  # Chain validation alone is insufficient under a private PKI: an enterprise
  # CA signs certificates for many hosts, so any holder of one could impersonate
  # an endpoint if only the chain were checked. Net::HTTP verifies the hostname
  # as well — pin that, because it is the half that a hand-rolled SSLContext
  # most often forgets.
  describe "a certificate issued for a DIFFERENT hostname" do
    it "is REJECTED even though it chains to the trusted CA" do
      TlsTestServer.https(ca: TlsTestServer.trusted_ca, sans: [ "DNS:not-our-host.example.com" ]) do |server|
        expect {
          described_class.start(server[:uri], ca_file: server[:ca_file]) do |http|
            http.request(Net::HTTP::Get.new(server[:uri]))
          end
        }.to raise_error(OpenSSL::SSL::SSLError, /hostname mismatch/i)
      end
    end
  end

  describe "a trusted server certificate" do
    it "is ACCEPTED — returns 200 when the issuing CA is supplied via ca_file" do
      TlsTestServer.https(ca: TlsTestServer.trusted_ca, body: '{"ok":true}') do |server|
        response = described_class.start(server[:uri], ca_file: server[:ca_file]) do |http|
          http.request(Net::HTTP::Get.new(server[:uri]))
        end

        expect(response.code).to eq("200")
        expect(response.body).to eq('{"ok":true}')
      end
    end
  end

  # #774: operators drop a private/inspection CA into /rails/certs and
  # bin/lib/ca-trust.sh folds it into a combined bundle exported as
  # SSL_CERT_FILE. spec/scripts/ca_trust_spec.rb proves the bundle is assembled
  # correctly from *placeholder* PEM text; it cannot prove a client then trusts
  # a leaf issued by that CA. This closes that loop with real certificates and a
  # real handshake.
  #
  # It must run in a CHILD process: OpenSSL reads SSL_CERT_FILE once, when it
  # builds SSLContext::DEFAULT_CERT_STORE at load time, so setting the variable
  # inside a running example has no effect. The entrypoint exports it before
  # Ruby boots, and that is what is reproduced here.
  describe "custom-CA trust (#774)" do
    # Drive the REAL ca-trust.sh over a directory holding the test CA and
    # return the path of the combined bundle it writes.
    def build_ca_bundle(ca_pem_path, dir)
      certs_dir = File.join(dir, "certs")
      FileUtils.mkdir_p(certs_dir)
      FileUtils.cp(ca_pem_path, File.join(certs_dir, "operator-ca.crt"))
      out = File.join(dir, "ca-bundle.pem")

      env = {
        "SPARC_EXTRA_CA_CERTS" => certs_dir,
        "SPARC_SYSTEM_CA_BUNDLE" => OpenSSL::X509::DEFAULT_CERT_FILE.to_s,
        "SPARC_CA_BUNDLE_OUT" => out
      }
      script = <<~BASH
        set -euo pipefail
        source #{Rails.root.join('bin/lib/ca-trust.sh').to_s.shellescape}
        sparc_setup_ca_trust
        echo "SSL_CERT_FILE=${SSL_CERT_FILE:-}"
      BASH
      stdout, _stderr, status = Open3.capture3(env, "bash", "-c", script)
      expect(status).to be_success
      expect(stdout).to include("SSL_CERT_FILE=#{out}")
      out
    end

    # Fetch `uri` with SparcHttp in a child process under the given env.
    # Returns "OK:<body>" or "SSLERROR:<message>".
    def fetch_in_child(uri, env)
      script = <<~RUBY
        require "uri"
        require "net/http"
        require "openssl"
        require #{Rails.root.join('app/lib/sparc_http.rb').to_s.dump}
        begin
          puts "OK:" + SparcHttp.get(ARGV[0])
        rescue OpenSSL::SSL::SSLError => e
          puts "SSLERROR:" + e.message
        end
      RUBY
      out, = Open3.capture2e(env, RbConfig.ruby, "-e", script, uri.to_s)
      out.strip
    end

    it "REJECTS a leaf from the operator CA when that CA is NOT installed" do
      TlsTestServer.https(ca: TlsTestServer.trusted_ca, body: "trusted") do |server|
        result = fetch_in_child(server[:uri], { "SSL_CERT_FILE" => nil })

        expect(result).to start_with("SSLERROR:")
        expect(result).to match(/certificate verify failed/i)
      end
    end

    it "ACCEPTS the same leaf once ca-trust.sh has installed the operator CA" do
      Dir.mktmpdir("sparc-ca-trust") do |dir|
        TlsTestServer.https(ca: TlsTestServer.trusted_ca, body: "trusted") do |server|
          bundle = build_ca_bundle(TlsTestServer.trusted_ca.ca_file, dir)

          expect(fetch_in_child(server[:uri], { "SSL_CERT_FILE" => bundle })).to eq("OK:trusted")
        end
      end
    end

    it "keeps the PUBLIC CA set trusted alongside the private one" do
      Dir.mktmpdir("sparc-ca-trust") do |dir|
        bundle = build_ca_bundle(TlsTestServer.trusted_ca.ca_file, dir)
        combined = File.read(bundle)

        # The operator CA is present...
        expect(combined).to include(File.read(TlsTestServer.trusted_ca.ca_file).strip)
        # ...and so is the whole system bundle it was appended to, so adding a
        # private CA cannot silently narrow trust for public endpoints.
        system_bundle = OpenSSL::X509::DEFAULT_CERT_FILE
        skip "no system CA bundle in this environment" unless File.file?(system_bundle)
        expect(combined.length).to be > File.size(system_bundle)
      end
    end
  end
end
