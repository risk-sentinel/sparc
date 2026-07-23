# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/db_url/config")

# #785 Pass 2 — DbUrl derives every database's connection from DATABASE_URL, with
# SPARC_DB_* as a still-supported fallback. This is the highest-risk change in the
# whole #785 programme: get it wrong and production cannot reach its cache, queue,
# or cable databases, because Rails only merges DATABASE_URL into `primary`.
RSpec.describe DbUrl do
  around do |ex|
    keys = %w[DATABASE_URL SPARC_DB_HOST SPARC_DB_PORT SPARC_DB_NAME SPARC_DB_USER
              SPARC_DB_PASSWORD SSP_TPR_MANAGER_DATABASE_PASSWORD]
    saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
    ex.run
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe "with DATABASE_URL set" do
    before do
      # %40 is an encoded '@' — a real special character in a password. It must
      # decode the same way Rails decodes it for `primary`, or the secondaries
      # authenticate with the wrong password.
      ENV["DATABASE_URL"] = "postgresql://appuser:s3cr%40t@db.internal:5433/sparc_prod?sslmode=require"
    end

    it "derives every component from the URL" do
      expect(described_class.host).to eq("db.internal")
      expect(described_class.port).to eq(5433)
      expect(described_class.database).to eq("sparc_prod")
      expect(described_class.username).to eq("appuser")
    end

    it "decodes a percent-encoded password identically to Rails" do
      expect(described_class.password).to eq("s3cr@t")
    end

    it "suffixes the secondary database names" do
      expect(described_class.cache_database).to eq("sparc_prod_cache")
      expect(described_class.queue_database).to eq("sparc_prod_queue")
      expect(described_class.cable_database).to eq("sparc_prod_cable")
    end

    it "wins over SPARC_DB_* when both are set" do
      ENV["SPARC_DB_HOST"] = "legacy-host"
      ENV["SPARC_DB_NAME"] = "legacy-db"
      expect(described_class.host).to eq("db.internal")
      expect(described_class.database).to eq("sparc_prod")
    end
  end

  describe "with only SPARC_DB_* set (DATABASE_URL unset — the fallback path)" do
    before do
      ENV["SPARC_DB_HOST"] = "legacy-host"
      ENV["SPARC_DB_PORT"] = "5544"
      ENV["SPARC_DB_NAME"] = "legacy-db"
      ENV["SPARC_DB_USER"] = "legacy-user"
      ENV["SPARC_DB_PASSWORD"] = "legacy-pass"
    end

    it "falls back to the individual variables so existing deployments keep working" do
      expect(described_class.host).to eq("legacy-host")
      expect(described_class.port).to eq("5544")
      expect(described_class.database).to eq("legacy-db")
      expect(described_class.username).to eq("legacy-user")
      expect(described_class.password).to eq("legacy-pass")
      expect(described_class.cache_database).to eq("legacy-db_cache")
    end

    it "honours the legacy SSP_TPR_MANAGER_DATABASE_PASSWORD alias" do
      ENV.delete("SPARC_DB_PASSWORD")
      ENV["SSP_TPR_MANAGER_DATABASE_PASSWORD"] = "aliased-pass"
      expect(described_class.password).to eq("aliased-pass")
    end
  end

  describe "with nothing set (bare defaults)" do
    it "uses the shipped defaults" do
      expect(described_class.host).to eq("localhost")
      expect(described_class.port).to eq(5432)
      expect(described_class.database).to eq("ssp_tpr_manager_production")
      expect(described_class.username).to eq("ssp_tpr_manager")
      expect(described_class.password).to be_nil
    end
  end

  describe "resilience" do
    it "falls back rather than crashing boot on a malformed DATABASE_URL" do
      ENV["DATABASE_URL"] = "::: not a url :::"
      expect { described_class.components }.not_to raise_error
      expect(described_class.host).to eq("localhost")
    end

    it "treats an empty DATABASE_URL as unset" do
      ENV["DATABASE_URL"] = ""
      expect(described_class.database).to eq("ssp_tpr_manager_production")
    end
  end
end

# database.yml must apply the derivation to ALL FOUR databases, and stay valid
# raw YAML (an editor / linter reads it without rendering ERB — #788).
RSpec.describe "database.yml DATABASE_URL derivation" do
  def resolve(rails_env, env = {})
    keys = %w[DATABASE_URL SPARC_DB_HOST SPARC_DB_PORT SPARC_DB_NAME SPARC_DB_USER
              SPARC_DB_PASSWORD SSP_TPR_MANAGER_DATABASE_PASSWORD]
    saved = keys.to_h { |k| [ k, ENV[k] ] }.merge("RAILS_ENV" => ENV["RAILS_ENV"])
    keys.each { |k| ENV.delete(k) }
    ENV["RAILS_ENV"] = rails_env
    env.each { |k, v| ENV[k] = v }
    yaml = YAML.load(ERB.new(File.read(Rails.root.join("config/database.yml"))).result, aliases: true)
    yaml.fetch(rails_env)
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  it "stays parseable as raw YAML (no <% %> statement block)" do
    expect {
      YAML.load_file(Rails.root.join("config/database.yml"), aliases: true)
    }.not_to raise_error
  end

  it "points all four production databases at the DATABASE_URL host" do
    prod = resolve("production", "DATABASE_URL" => "postgresql://u:p@dbhost:5433/mydb")
    %w[primary cache queue cable].each do |name|
      expect(prod[name]["host"]).to eq("dbhost"), "#{name} not derived from DATABASE_URL"
      expect(prod[name]["username"]).to eq("u")
    end
  end

  it "gives the secondaries suffixed database names off the DATABASE_URL name" do
    prod = resolve("production", "DATABASE_URL" => "postgresql://u:p@h/mydb")
    expect(prod["primary"]["database"]).to eq("mydb")
    expect(prod["cache"]["database"]).to eq("mydb_cache")
    expect(prod["queue"]["database"]).to eq("mydb_queue")
    expect(prod["cable"]["database"]).to eq("mydb_cable")
  end

  it "still resolves all four from SPARC_DB_* when DATABASE_URL is unset" do
    prod = resolve("production", "SPARC_DB_HOST" => "legacy", "SPARC_DB_NAME" => "legacydb")
    %w[primary cache queue cable].each { |n| expect(prod[n]["host"]).to eq("legacy") }
    expect(prod["cable"]["database"]).to eq("legacydb_cable")
  end
end
