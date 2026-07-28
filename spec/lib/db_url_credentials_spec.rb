# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/db_url/config")

# #834 — SPARC builds its RDS connection from the structured DB_CREDENTIALS
# secret rather than a pre-rendered plaintext DATABASE_URL.
#
# The point is rotation: DATABASE_URL is rendered at deploy time and therefore
# PINS the password, so a Secrets Manager rotation does not take effect until
# the next redeploy. Reading the secret at boot means a restart is enough.
RSpec.describe DbUrl, "DB_CREDENTIALS (#834)" do
  # DbUrl caches its parse keyed on the raw value, so tests must not leak state
  # into each other through that cache or through ENV.
  around do |example|
    saved = ENV.to_hash.slice(*%w[
      DB_CREDENTIALS DATABASE_URL
      SPARC_DB_NAME SPARC_DB_USER SPARC_DB_HOST SPARC_DB_PORT SPARC_DB_PASSWORD
      SSP_TPR_MANAGER_DATABASE_PASSWORD
    ])
    %w[DB_CREDENTIALS DATABASE_URL SPARC_DB_NAME SPARC_DB_USER SPARC_DB_HOST
       SPARC_DB_PORT SPARC_DB_PASSWORD SSP_TPR_MANAGER_DATABASE_PASSWORD].each { |k| ENV.delete(k) }

    example.run
  ensure
    %w[DB_CREDENTIALS DATABASE_URL SPARC_DB_NAME SPARC_DB_USER SPARC_DB_HOST
       SPARC_DB_PORT SPARC_DB_PASSWORD SSP_TPR_MANAGER_DATABASE_PASSWORD].each { |k| ENV.delete(k) }
    saved.each { |k, v| ENV[k] = v }
  end

  def set_credentials(overrides = {})
    ENV["DB_CREDENTIALS"] = {
      "host" => "rds.internal", "port" => 5432, "dbname" => "sparc_prod",
      "username" => "sparc_app", "password" => "s3cret"
    }.merge(overrides).to_json
  end

  describe "as the connection source" do
    it "builds every component from the secret with no DATABASE_URL present" do
      set_credentials

      expect(DbUrl.host).to eq("rds.internal")
      expect(DbUrl.port).to eq(5432)
      expect(DbUrl.database).to eq("sparc_prod")
      expect(DbUrl.username).to eq("sparc_app")
      expect(DbUrl.password).to eq("s3cret")
    end

    # The acceptance criterion: rotate the secret, restart, connect with the new
    # password — no config change and no redeploy.
    it "picks up a rotated password without any other change" do
      set_credentials
      expect(DbUrl.password).to eq("s3cret")

      set_credentials("password" => "rotated--9f2")

      expect(DbUrl.password).to eq("rotated--9f2"),
        "a rotated secret was not picked up — the parse cache is stale, which " \
        "would mean rotation still requires a redeploy"
    end

    it "still derives the secondary databases from the secret" do
      set_credentials

      expect(DbUrl.cache_database).to eq("sparc_prod_cache")
      expect(DbUrl.queue_database).to eq("sparc_prod_queue")
      expect(DbUrl.cable_database).to eq("sparc_prod_cable")
    end

    it "reads a port that the secret quoted as a string" do
      set_credentials("port" => "6543")

      expect(DbUrl.port).to eq(6543)
    end
  end

  describe "precedence" do
    it "prefers DB_CREDENTIALS over DATABASE_URL" do
      ENV["DATABASE_URL"] = "postgres://old_user:old_pass@old.host:5432/old_db"
      set_credentials

      expect(DbUrl.host).to eq("rds.internal")
      expect(DbUrl.username).to eq("sparc_app")
      expect(DbUrl.password).to eq("s3cret")
    end

    it "falls back to DATABASE_URL when the secret is absent" do
      ENV["DATABASE_URL"] = "postgres://old_user:old_pass@old.host:5432/old_db"

      expect(DbUrl.host).to eq("old.host")
      expect(DbUrl.username).to eq("old_user")
    end

    it "falls back to SPARC_DB_* when neither is set" do
      ENV["SPARC_DB_HOST"] = "legacy.host"
      ENV["SPARC_DB_PASSWORD"] = "legacy-pass"

      expect(DbUrl.host).to eq("legacy.host")
      expect(DbUrl.password).to eq("legacy-pass")
    end
  end

  # Rails merges DATABASE_URL into `primary` ONLY. Left alone, `primary` would
  # use the stale deploy-time password while cache/queue/cable used the rotated
  # one, and the app would half-connect.
  describe "#reconcile_database_url!" do
    it "removes a competing DATABASE_URL so one source wins outright" do
      ENV["DATABASE_URL"] = "postgres://old_user:old_pass@old.host:5432/old_db"
      set_credentials

      DbUrl.reconcile_database_url!

      expect(ENV["DATABASE_URL"]).to be_nil,
        "Rails merges DATABASE_URL into `primary` only, so leaving it set puts " \
        "primary on the stale password while cache/queue/cable use the rotated one"
    end

    it "leaves DATABASE_URL alone when there is no secret" do
      ENV["DATABASE_URL"] = "postgres://only:one@source.host:5432/db"

      DbUrl.reconcile_database_url!

      expect(ENV["DATABASE_URL"]).to eq("postgres://only:one@source.host:5432/db")
    end

    # Rotated passwords are machine-generated and routinely contain characters
    # that are special in a URL. Because the secret's fields are passed to libpq
    # discretely and no URL is ever built from them, there is nothing to encode
    # and nothing to get wrong — this proves the value survives untouched.
    it "carries a password full of URL-special characters through untouched" do
      hostile = 'p@ss:w/rd#frag?q=1&x +%20"\'<>[]{}'
      set_credentials("password" => hostile, "username" => "user@corp")

      expect(DbUrl.password).to eq(hostile)
      expect(DbUrl.username).to eq("user@corp")
      expect(DbUrl.host).to eq("rds.internal")
    end
  end

  # Precedence is deliberate but invisible at runtime; these are what the boot
  # posture check reports so an operator can see which variable is actually in
  # use rather than debugging one that is being ignored.
  describe "#source and #overridden_sources" do
    it "reports db_credentials as the source, and names the losers" do
      ENV["DATABASE_URL"] = "postgres://u:p@h:5432/d"
      ENV["SPARC_DB_HOST"] = "legacy.host"
      set_credentials

      expect(DbUrl.source).to eq(:db_credentials)
      expect(DbUrl.overridden_sources).to contain_exactly(:database_url, :sparc_db_vars)
    end

    # The removal destroys the evidence, so the conflict has to be remembered
    # at the moment it happens or it can never be reported.
    it "still reports DATABASE_URL as overridden after it has been removed" do
      ENV["DATABASE_URL"] = "postgres://u:p@h:5432/d"
      set_credentials
      DbUrl.reconcile_database_url!

      expect(ENV["DATABASE_URL"]).to be_nil
      expect(DbUrl.overridden_sources).to include(:database_url)
    end

    it "reports database_url when there is no secret" do
      ENV["DATABASE_URL"] = "postgres://u:p@h:5432/d"

      expect(DbUrl.source).to eq(:database_url)
      expect(DbUrl.overridden_sources).to be_empty
    end

    it "reports sparc_db_vars when it is the only source" do
      ENV["SPARC_DB_HOST"] = "legacy.host"

      expect(DbUrl.source).to eq(:sparc_db_vars)
    end

    it "reports defaults when nothing is configured" do
      expect(DbUrl.source).to eq(:defaults)
    end

    # The SPARC_DB_* block has no all-or-nothing guard: a missing password
    # connects with NO password rather than failing.
    it "names the missing members of a partial SPARC_DB_* block" do
      ENV["SPARC_DB_HOST"] = "legacy.host"
      ENV["SPARC_DB_USER"] = "app"

      expect(DbUrl.sparc_db_vars_missing).to contain_exactly("SPARC_DB_NAME", "SPARC_DB_PASSWORD")
    end

    it "does not treat an unset port as missing — 5432 is unambiguous" do
      %w[SPARC_DB_HOST SPARC_DB_NAME SPARC_DB_USER SPARC_DB_PASSWORD].each { |k| ENV[k] = "x" }

      expect(DbUrl.sparc_db_vars_missing).to be_empty
    end

    it "reports nothing missing when the block is untouched" do
      expect(DbUrl.sparc_db_vars_missing).to be_empty
    end
  end

  describe "a malformed secret" do
    # Warn, never raise — matching the DATABASE_URL path and the database TLS
    # posture check. A bad secret must not become a cryptic YAML/ERB boot error.
    it "falls back instead of raising when the JSON is invalid" do
      ENV["SPARC_DB_HOST"] = "fallback.host"
      ENV["DB_CREDENTIALS"] = "{not json"

      expect { DbUrl.host }.not_to raise_error
      expect(DbUrl.host).to eq("fallback.host")
    end

    it "falls back when the JSON is valid but not an object" do
      ENV["SPARC_DB_HOST"] = "fallback.host"
      ENV["DB_CREDENTIALS"] = '["a", "b"]'

      expect(DbUrl.host).to eq("fallback.host")
    end

    # All or nothing. A partial secret blended with DATABASE_URL would connect
    # using half of each credential, and fail somewhere unrelated.
    it "ignores the whole secret when a required field is blank" do
      ENV["DATABASE_URL"] = "postgres://url_user:url_pass@url.host:5432/url_db"
      set_credentials("host" => "   ")

      expect(DbUrl.host).to eq("url.host")
      expect(DbUrl.username).to eq("url_user"),
        "a blank host must not leave the OTHER secret fields in play — that is a blended credential"
    end

    it "ignores the whole secret when a required field is absent" do
      ENV["DATABASE_URL"] = "postgres://url_user:url_pass@url.host:5432/url_db"
      ENV["DB_CREDENTIALS"] = { "host" => "rds.internal", "dbname" => "sparc_prod" }.to_json

      expect(DbUrl.username).to eq("url_user")
      expect(DbUrl.password).to eq("url_pass")
    end

    it "accepts a secret with no port and defaults to 5432" do
      set_credentials.then { ENV["DB_CREDENTIALS"] = JSON.parse(ENV.fetch("DB_CREDENTIALS")).except("port").to_json }

      expect(DbUrl.port).to eq(5432)
      expect(DbUrl.host).to eq("rds.internal")
    end

    it "never echoes the secret in its warning" do
      set_credentials
      secret = ENV.fetch("DB_CREDENTIALS")
      ENV["DB_CREDENTIALS"] = "{not json, but the password is s3cret"

      expect { DbUrl.host }.to output(/DB_CREDENTIALS is not valid JSON/).to_stderr
      expect { DbUrl.host }.not_to output(/s3cret/).to_stderr

      expect(secret).to include("s3cret") # guards the assertion above being vacuous
    end
  end
end
