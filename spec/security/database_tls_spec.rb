# frozen_string_literal: true

require "rails_helper"
require "pg"

# #785 — DB transport security, proven in BOTH directions with real handshakes.
#
# A config assertion ("sslmode is set to require") proves nothing: it does not
# show that the server is actually reached over TLS, nor that an insecure
# connection is genuinely refused rather than silently downgraded. So this suite
# runs a real libpq handshake against two live Postgres servers — one with TLS
# enabled, one plaintext-only — and asserts both the accept and the reject side.
#
# Run it with:  bin/test-db-tls
# (which stands up the two servers, then re-invokes rspec with SPARC_DB_TLS_TEST=1)
#
# NIST 800-53: SC-8 (transmission confidentiality), SC-8(1) (cryptographic
# protection), SC-13. FedRAMP High requires encryption in transit to the
# database; `require` alone encrypts but does not authenticate the server, so
# verify-full is the target and is exercised here.
RSpec.describe "Database TLS enforcement", :db_tls do
  TLS_PORT   = ENV.fetch("SPARC_DB_TLS_PORT", "5434")
  PLAIN_PORT = ENV.fetch("SPARC_DB_PLAIN_PORT", "5435")
  CA_FILE    = ENV["SPARC_DB_TLS_CA"]

  before(:all) do
    unless ENV["SPARC_DB_TLS_TEST"] == "1"
      skip "Set SPARC_DB_TLS_TEST=1 (see bin/test-db-tls) — needs live TLS + plaintext Postgres"
    end
  end

  def connect(**opts)
    PG.connect(user: "postgres", password: "secret", dbname: "postgres",  # gitleaks:allow
               connect_timeout: 5, **opts)
  end

  # Returns true only if the backend reports the session as SSL-protected.
  # Asking the server is the point — we do not trust the client's intent.
  def encrypted?(conn)
    conn.exec("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()").first["ssl"] == "t"
  end

  describe "accepts a properly secured connection" do
    it "connects over TLS and authenticates the server with verify-full" do
      skip "no CA file provided" unless CA_FILE

      conn = connect(host: "localhost", port: TLS_PORT,
                     sslmode: "verify-full", sslrootcert: CA_FILE)
      expect(encrypted?(conn)).to be(true)
      conn.close
    end

    it "connects over TLS with sslmode=require" do
      conn = connect(host: "localhost", port: TLS_PORT, sslmode: "require")
      expect(encrypted?(conn)).to be(true)
      conn.close
    end
  end

  # The half that actually matters. Each of these MUST raise.
  describe "refuses an insecure connection" do
    it "refuses to fall back to plaintext when sslmode=require" do
      expect {
        connect(host: "localhost", port: PLAIN_PORT, sslmode: "require")
      }.to raise_error(PG::Error, /SSL was required|does not support SSL/i)
    end

    it "refuses verify-full when no CA is supplied" do
      expect {
        connect(host: "localhost", port: TLS_PORT, sslmode: "verify-full")
      }.to raise_error(PG::Error, /root certificate/i)
    end

    it "refuses verify-full when the CA does not sign the server cert" do
      skip "no CA file provided" unless CA_FILE

      expect {
        connect(host: "localhost", port: TLS_PORT,
                sslmode: "verify-full", sslrootcert: "/etc/ssl/cert.pem")
      }.to raise_error(PG::Error, /certificate verify failed/i)
    end

    it "refuses verify-full when the hostname does not match the certificate" do
      skip "no CA file provided" unless CA_FILE

      # Same server, same CA — only the host string differs. This is the check
      # that distinguishes verify-full from verify-ca, and the one that stops an
      # attacker presenting a valid cert for a host they do control.
      expect {
        connect(host: "127.0.0.1", port: TLS_PORT,
                sslmode: "verify-full", sslrootcert: CA_FILE)
      }.to raise_error(PG::Error, /does not match host name/i)
    end
  end

  # Without this the suite could pass while silently testing nothing: if the
  # "plaintext" server were actually TLS-enabled, every negative case above
  # would raise for the wrong reason. This proves the harness sees a downgrade.
  describe "control" do
    it "detects a plaintext downgrade when sslmode=prefer" do
      conn = connect(host: "localhost", port: PLAIN_PORT, sslmode: "prefer")
      expect(encrypted?(conn)).to be(false)
      conn.close
    end
  end
end

# Configuration-level companion: proves the floor is applied to EVERY database,
# not just primary. Runs anywhere, no servers needed.
RSpec.describe "database.yml TLS floor" do
  # Throwaway credentials, supplied so the PRODUCTION branch of database.yml can
  # be evaluated at all.
  #
  # `DbUrl.password` raises MissingPasswordError when nothing is configured
  # (#849, fail-closed: a Postgres server set to `trust` would accept an empty
  # password, so SPARC refuses to start rather than serve traffic against an
  # unauthenticated connection). That guard is correct and is covered by
  # spec/lib/db_url_fail_closed_spec.rb — it is not what THIS file is about,
  # which is the TLS floor applying to every database.
  #
  # Without these, the production examples depended on the developer's ambient
  # shell happening to export DB credentials, and failed in any environment that
  # did not. Setting them here makes the file self-sufficient.
  ENV_KEYS = %w[
    RAILS_ENV SPARC_DB_SSLMODE SPARC_DB_SSLROOTCERT
    SPARC_DB_HOST SPARC_DB_NAME SPARC_DB_USER SPARC_DB_PASSWORD
  ].freeze

  def resolve(rails_env, sslmode: nil, rootcert: nil)
    old = ENV.to_h.slice(*ENV_KEYS)
    ENV["RAILS_ENV"] = rails_env
    ENV["SPARC_DB_HOST"]     = "localhost"
    ENV["SPARC_DB_NAME"]     = "sparc_tls_floor_spec"
    ENV["SPARC_DB_USER"]     = "postgres"
    ENV["SPARC_DB_PASSWORD"] = "password" # gitleaks:allow — throwaway, never connects
    sslmode  ? ENV["SPARC_DB_SSLMODE"] = sslmode      : ENV.delete("SPARC_DB_SSLMODE")
    rootcert ? ENV["SPARC_DB_SSLROOTCERT"] = rootcert : ENV.delete("SPARC_DB_SSLROOTCERT")
    yaml = YAML.load(ERB.new(File.read(Rails.root.join("config/database.yml"))).result, aliases: true)
    yaml.fetch(rails_env)
  ensure
    ENV_KEYS.each { |key| ENV.delete(key) }
    old.each { |k, v| ENV[k] = v }
  end

  it "floors production at require for primary AND every secondary database" do
    prod = resolve("production")
    expect(prod.keys).to include("primary", "cache", "queue", "cable")
    prod.each_value { |cfg| expect(cfg["sslmode"]).to eq("require") }
  end

  it "leaves development and test at prefer so local Postgres still connects" do
    expect(resolve("development")["sslmode"]).to eq("prefer")
    expect(resolve("test")["sslmode"]).to eq("prefer")
  end

  it "lets an operator raise production to verify-full across all databases" do
    prod = resolve("production", sslmode: "verify-full", rootcert: "/etc/ssl/certs/rds.pem")
    prod.each_value do |cfg|
      expect(cfg["sslmode"]).to eq("verify-full")
      expect(cfg["sslrootcert"]).to eq("/etc/ssl/certs/rds.pem")
    end
  end

  it "leaves sslrootcert nil when unset, which Rails drops before connecting" do
    # The key is emitted unconditionally so the file stays valid raw YAML (an
    # ERB `if` would put a bare `<% %>` line into the mapping). A nil value is
    # harmless: postgresql_adapter.rb does `conn_params = @config.compact`, so
    # it never reaches libpq.
    expect(resolve("production")["primary"]["sslrootcert"]).to be_nil
  end

  it "keeps config/database.yml parseable as raw YAML" do
    # Editors and YAML tooling parse this file WITHOUT rendering ERB first. An
    # unquoted ternary containing a `:` breaks them, which is exactly what
    # happened when the TLS floor was first added.
    expect {
      YAML.load_file(Rails.root.join("config/database.yml"), aliases: true)
    }.not_to raise_error
  end
end
