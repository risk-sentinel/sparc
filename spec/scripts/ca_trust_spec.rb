# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# Unit test for bin/lib/ca-trust.sh (#774, runtime custom-CA trust). Sources the
# shell lib and drives sparc_setup_ca_trust in a sandbox tmpdir with a fake
# system bundle + fake custom CAs, asserting on the combined bundle it writes and
# the SSL_CERT_FILE it exports. No root or real certs required.
RSpec.describe "bin/lib/ca-trust.sh" do
  let(:lib) { Rails.root.join("bin/lib/ca-trust.sh").to_s }

  # Run sparc_setup_ca_trust with the given env; return {stdout:, ssl_cert_file:,
  # status:}. SSL_CERT_FILE is echoed from inside the same shell so we capture
  # the exported value.
  def run_setup(env)
    script = <<~BASH
      set -euo pipefail
      source #{lib.shellescape}
      sparc_setup_ca_trust
      echo "SSL_CERT_FILE=${SSL_CERT_FILE:-}"
    BASH
    out, err, status = Open3.capture3(env, "bash", "-c", script)
    ssl = out[/^SSL_CERT_FILE=(.*)$/, 1]
    { stdout: out, stderr: err, ssl_cert_file: ssl.to_s, status: status }
  end

  around do |example|
    Dir.mktmpdir("ca-trust") do |dir|
      @dir = dir
      # Keep the system bundle OUTSIDE the custom-CA dir so it is not itself
      # collected as a custom CA.
      @sys_bundle = File.join(dir, "system-cert.pem")
      File.write(@sys_bundle, "# SYSTEM PUBLIC CA\n-----BEGIN CERTIFICATE-----\nSYSTEMCA\n-----END CERTIFICATE-----\n")
      @certs_dir = File.join(dir, "certs")
      FileUtils.mkdir_p(@certs_dir)
      @out = File.join(dir, "out", "ca-bundle.pem")
      example.run
    end
  end

  def base_env(extra = {})
    {
      "SPARC_SYSTEM_CA_BUNDLE" => @sys_bundle,
      "SPARC_CA_BUNDLE_OUT" => @out
    }.merge(extra)
  end

  def write_ca(name, body)
    path = File.join(@certs_dir, name)
    File.write(path, "-----BEGIN CERTIFICATE-----\n#{body}\n-----END CERTIFICATE-----\n")
    path
  end

  it "is a no-op when no custom CA source is supplied" do
    # Point the default mount at a nonexistent dir so /rails/certs can't leak in.
    result = run_setup(base_env("SPARC_EXTRA_CA_CERTS" => File.join(@dir, "does-not-exist")))
    expect(result[:status]).to be_success
    expect(result[:ssl_cert_file]).to eq("")
    expect(File).not_to exist(@out)
  end

  it "combines system + custom CA (dir source) and exports SSL_CERT_FILE" do
    write_ca("internal-root.crt", "INTERNALCA")
    result = run_setup(base_env("SPARC_EXTRA_CA_CERTS" => @certs_dir))

    expect(result[:status]).to be_success
    expect(result[:ssl_cert_file]).to eq(@out)
    expect(File).to exist(@out)

    bundle = File.read(@out)
    expect(bundle).to include("SYSTEMCA")    # public CAs preserved (append, not replace)
    expect(bundle).to include("INTERNALCA")  # custom CA added
    # System CAs must come first so they are not shadowed.
    expect(bundle.index("SYSTEMCA")).to be < bundle.index("INTERNALCA")
  end

  it "accepts a single file as the source" do
    ca = write_ca("one.pem", "SINGLECA")
    result = run_setup(base_env("SPARC_EXTRA_CA_CERTS" => ca))
    expect(result[:status]).to be_success
    expect(result[:ssl_cert_file]).to eq(@out)
    expect(File.read(@out)).to include("SINGLECA")
  end

  it "ignores non-certificate files (README, .gitkeep) in the dir" do
    File.write(File.join(@certs_dir, "README.md"), "not a cert")
    File.write(File.join(@certs_dir, ".gitkeep"), "")
    result = run_setup(base_env("SPARC_EXTRA_CA_CERTS" => @certs_dir))
    # No .crt/.pem/.cer present -> treated as empty, no bundle written.
    expect(result[:status]).to be_success
    expect(result[:ssl_cert_file]).to eq("")
    expect(File).not_to exist(@out)
    expect(result[:stdout]).to match(/no PEM\/CRT files/)
  end

  it "picks up multiple custom CAs" do
    write_ca("a.crt", "CA_A")
    write_ca("b.pem", "CA_B")
    result = run_setup(base_env("SPARC_EXTRA_CA_CERTS" => @certs_dir))
    bundle = File.read(@out)
    expect(bundle).to include("CA_A").and include("CA_B")
    expect(result[:stdout]).to match(/trusting 2 custom CA file/)
  end
end
