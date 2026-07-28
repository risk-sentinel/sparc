# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/db_url/config")

# #849 — production refuses to start when no database password resolves.
#
# The failure this prevents is silent by construction: nil reaches libpq, a
# PostgreSQL server on `trust` authentication accepts it, and the app boots,
# passes health checks and serves traffic against an unauthenticated database.
# Nothing about the running system looks wrong. So the tests that matter here
# are the NEGATIVE ones — that it refuses — and they are written first.
#
# `production?` reads ENV["RAILS_ENV"] directly rather than Rails.env, which is
# what makes this testable at all: the suite runs in the test environment and
# can still exercise the production branch honestly, without stubbing the
# method under test.
RSpec.describe DbUrl, "#849 fail-closed password" do
  around do |example|
    keys = %w[
      RAILS_ENV SECRET_KEY_BASE_DUMMY DB_CREDENTIALS DATABASE_URL
      SPARC_DB_HOST SPARC_DB_PORT SPARC_DB_NAME SPARC_DB_USER SPARC_DB_PASSWORD
      SSP_TPR_MANAGER_DATABASE_PASSWORD SPARC_DB_ALLOW_EMPTY_PASSWORD
    ]
    saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
    example.run
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # A complete SPARC_DB_* block apart from the password, which each example
  # then supplies, omits, or blanks.
  def configure_sparc_db_block(password: :omit)
    ENV["SPARC_DB_HOST"] = "db.internal"
    ENV["SPARC_DB_NAME"] = "sparc_prod"
    ENV["SPARC_DB_USER"] = "appuser"
    ENV["SPARC_DB_PASSWORD"] = password unless password == :omit
  end

  describe "in production" do
    before { ENV["RAILS_ENV"] = "production" }

    it "refuses to boot when the SPARC_DB_* block has no password" do
      configure_sparc_db_block

      expect { described_class.password }.to raise_error(DbUrl::MissingPasswordError)
    end

    it "refuses when SPARC_DB_PASSWORD is set but EMPTY" do
      # The regression this pins: "" is truthy in Ruby, so the previous `||`
      # chain returned it as a real password and never reached the fallbacks.
      configure_sparc_db_block(password: "")

      expect { described_class.password }.to raise_error(DbUrl::MissingPasswordError)
    end

    it "refuses when SPARC_DB_PASSWORD is only whitespace" do
      configure_sparc_db_block(password: "   ")

      expect { described_class.password }.to raise_error(DbUrl::MissingPasswordError)
    end

    it "refuses when nothing is configured at all" do
      expect { described_class.password }.to raise_error(DbUrl::MissingPasswordError, /no database configuration is set at all/i)
    end

    it "refuses when DATABASE_URL carries no password component" do
      ENV["DATABASE_URL"] = "postgresql://appuser@db.internal:5432/sparc_prod"

      expect { described_class.password }
        .to raise_error(DbUrl::MissingPasswordError, /DATABASE_URL is set but carries no password/)
    end

    # The case the issue calls hardest to notice: a malformed DB_CREDENTIALS
    # only WARNS and falls through, so the operator sees a secret configured and
    # a running app, with the fallback silently supplying no password.
    it "refuses when a malformed DB_CREDENTIALS falls through to a passwordless block" do
      ENV["DB_CREDENTIALS"] = "{ not json"
      configure_sparc_db_block

      expect { suppress_warnings { described_class.password } }
        .to raise_error(DbUrl::MissingPasswordError)
    end

    it "connects normally when a password IS set" do
      configure_sparc_db_block(password: "s3cr3t")

      expect(described_class.password).to eq("s3cr3t")
    end

    it "still accepts a password containing YAML metacharacters" do
      # Guards the #834 quoting fix from regressing through this path.
      configure_sparc_db_block(password: "&anchor: *star")

      expect(described_class.password).to eq("&anchor: *star")
    end

    describe "the refusal message" do
      subject(:message) do
        configure_sparc_db_block
        described_class.password
        nil
      rescue DbUrl::MissingPasswordError => e
        e.message
      end

      it "names the variable that is unset" do
        expect(message).to include("SPARC_DB_PASSWORD")
      end

      it "names the configuration source that resolved" do
        expect(message).to include("Resolved configuration source: sparc_db_vars")
      end

      it "explains why an unauthenticated connection would otherwise succeed" do
        expect(message).to match(/trust.*authentication would ACCEPT an\s+empty password/m)
      end

      it "offers every supported way to configure it" do
        expect(message).to include("DB_CREDENTIALS").and include("DATABASE_URL")
      end

      it "names the explicit opt-out rather than leaving it undiscoverable" do
        expect(message).to include("SPARC_DB_ALLOW_EMPTY_PASSWORD=true")
      end
    end

    describe "the explicit opt-out" do
      before { configure_sparc_db_block }

      %w[true 1 yes TRUE Yes].each do |value|
        it "permits a passwordless connection when set to #{value.inspect}" do
          ENV["SPARC_DB_ALLOW_EMPTY_PASSWORD"] = value

          expect(described_class.password).to be_nil
        end
      end

      # An opt-out that accepts anything non-empty would turn a typo into a
      # silent downgrade — exactly the failure mode this issue exists to close.
      %w[false 0 no maybe please].each do |value|
        it "still refuses when set to #{value.inspect}" do
          ENV["SPARC_DB_ALLOW_EMPTY_PASSWORD"] = value

          expect { described_class.password }.to raise_error(DbUrl::MissingPasswordError)
        end
      end
    end

    it "does not refuse during assets:precompile" do
      # SECRET_KEY_BASE_DUMMY marks the image build, which boots production to
      # compile assets with no database configured and none needed. Refusing
      # here would break the BUILD rather than a deployment.
      configure_sparc_db_block
      ENV["SECRET_KEY_BASE_DUMMY"] = "1"

      expect(described_class.password).to be_nil
    end
  end

  describe "outside production" do
    # A local PostgreSQL on `trust` auth is legitimate and ubiquitous. Same
    # precedent as the sslmode floor: strict in production, permissive here.
    %w[development test].each do |environment|
      it "returns nil without raising in #{environment}" do
        ENV["RAILS_ENV"] = environment
        configure_sparc_db_block

        expect(described_class.password).to be_nil
        expect(described_class.password_required?).to be(false)
      end
    end
  end

  describe "#resolved_password" do
    before { ENV["RAILS_ENV"] = "production" }

    # The posture check calls this on every production boot. If it raised, the
    # diagnostic would become the outage.
    it "never raises, so the boot posture check is safe to call it" do
      configure_sparc_db_block

      expect { described_class.resolved_password }.not_to raise_error
      expect(described_class.resolved_password).to be_nil
    end

    it "falls back to the legacy SSP_TPR_MANAGER_DATABASE_PASSWORD" do
      configure_sparc_db_block
      ENV["SSP_TPR_MANAGER_DATABASE_PASSWORD"] = "legacy-pass"

      expect(described_class.resolved_password).to eq("legacy-pass")
      expect { described_class.password }.not_to raise_error
    end
  end

  # Helper: parse_credentials warns to stderr on a malformed secret, which is
  # correct behaviour but noise in the suite output.
  def suppress_warnings
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end
end
