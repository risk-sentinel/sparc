require "rails_helper"

RSpec.describe SparcKeyDerivation do
  before { described_class.reset! }
  after  { described_class.reset! }

  describe ".derive" do
    it "produces a 32-byte key by default" do
      key = described_class.derive("test_purpose_a")
      expect(key.bytesize).to eq(32)
    end

    it "honours an explicit length" do
      key = described_class.derive("test_purpose_b", length: 16)
      expect(key.bytesize).to eq(16)
    end

    it "produces stable output for the same purpose" do
      a = described_class.derive("stable")
      b = described_class.derive("stable")
      expect(a).to eq(b)
    end

    it "produces different keys for different purposes" do
      a = described_class.derive("purpose_one")
      b = described_class.derive("purpose_two")
      expect(a).not_to eq(b)
    end

    it "raises on a blank purpose" do
      expect { described_class.derive("") }.to raise_error(ArgumentError)
      expect { described_class.derive(nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".master_secret_configured?" do
    around do |ex|
      previous = ENV["SPARC_HASH"]
      ENV["SPARC_HASH"] = nil
      ex.run
      ENV["SPARC_HASH"] = previous
    end

    it "is false when SPARC_HASH is unset" do
      expect(described_class.master_secret_configured?).to eq(false)
    end

    it "is false when SPARC_HASH is too short" do
      ENV["SPARC_HASH"] = "short"
      expect(described_class.master_secret_configured?).to eq(false)
    end

    it "is true when SPARC_HASH is at least 32 chars" do
      ENV["SPARC_HASH"] = "x" * 32
      expect(described_class.master_secret_configured?).to eq(true)
    end
  end

  describe "domain separation" do
    it "binds keys to the SPARC version-prefixed purpose" do
      raw_generator = ActiveSupport::KeyGenerator.new(
        ENV["SPARC_HASH"].to_s.length >= 32 ? ENV["SPARC_HASH"] : Rails.application.secret_key_base,
        hash_digest_class: OpenSSL::Digest::SHA256
      )
      derived  = described_class.derive("collision_test")
      naked    = raw_generator.generate_key("collision_test", 32)

      expect(derived).not_to eq(naked)
    end
  end
end
