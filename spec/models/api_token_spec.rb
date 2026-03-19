# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiToken, type: :model do
  let(:user) { create(:user) }

  describe ".generate!" do
    it "creates a token with a digest" do
      token = described_class.generate!(user: user, name: "Test Token")

      expect(token).to be_persisted
      expect(token.token_digest).to be_present
      expect(token.name).to eq("Test Token")
      expect(token.user).to eq(user)
    end

    it "makes plaintext_token available after generation" do
      token = described_class.generate!(user: user, name: "Test Token")

      expect(token.plaintext_token).to be_present
      expect(token.plaintext_token).to start_with("sparc_")
    end

    it "stores a SHA-256 digest, not the plaintext" do
      token = described_class.generate!(user: user, name: "Test Token")
      expected_digest = Digest::SHA256.hexdigest(token.plaintext_token)

      expect(token.token_digest).to eq(expected_digest)
      expect(token.token_digest).not_to eq(token.plaintext_token)
    end
  end

  describe ".authenticate" do
    it "finds a valid token by plaintext" do
      token = described_class.generate!(user: user, name: "Auth Test")
      found = described_class.authenticate(token.plaintext_token)

      expect(found).to eq(token)
      expect(found.user).to eq(user)
    end

    it "returns nil for an invalid token" do
      expect(described_class.authenticate("sparc_invalid_token")).to be_nil
    end

    it "returns nil for blank input" do
      expect(described_class.authenticate("")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
    end

    it "does not return expired tokens" do
      token = described_class.generate!(user: user, name: "Expired", expires_at: 1.hour.ago)
      expect(described_class.authenticate(token.plaintext_token)).to be_nil
    end

    it "returns tokens that have not yet expired" do
      token = described_class.generate!(user: user, name: "Future", expires_at: 1.day.from_now)
      expect(described_class.authenticate(token.plaintext_token)).to eq(token)
    end
  end

  describe "#touch_usage!" do
    it "updates last_used_at and last_used_ip" do
      token = described_class.generate!(user: user, name: "Usage Test")
      expect(token.last_used_at).to be_nil

      token.touch_usage!(ip: "192.168.1.1")
      token.reload

      expect(token.last_used_at).to be_within(2.seconds).of(Time.current)
      expect(token.last_used_ip).to eq("192.168.1.1")
    end
  end

  describe "#expired?" do
    it "returns false when expires_at is nil" do
      token = described_class.generate!(user: user, name: "No Expiry")
      expect(token.expired?).to be false
    end

    it "returns false when expires_at is in the future" do
      token = described_class.generate!(user: user, name: "Future", expires_at: 1.day.from_now)
      expect(token.expired?).to be false
    end

    it "returns true when expires_at is in the past" do
      token = described_class.generate!(user: user, name: "Past", expires_at: 1.hour.ago)
      expect(token.expired?).to be true
    end
  end
end
