# frozen_string_literal: true

require "rails_helper"

# #587 — classifier turns a (user, password) pair into a small fixed
# enum of audit-log reason codes.
RSpec.describe LoginFailureReason do
  describe ".classify" do
    it "returns 'unknown_email' when no user is supplied" do
      expect(described_class.classify(user: nil, password: "anything")).to eq("unknown_email")
    end

    it "returns 'no_local_password' for a user with no password_digest (OAuth-only)" do
      user = create(:user, password_digest: nil)
      expect(described_class.classify(user: user, password: "anything")).to eq("no_local_password")
    end

    it "returns 'suspended' for a suspended user (admin disabled / auto-deactivated)" do
      user = create(:user, status: "suspended")
      expect(described_class.classify(user: user, password: "wrong")).to eq("suspended")
    end

    it "returns 'invalid_password' when the password doesn't verify" do
      user = create(:user, status: "active")
      expect(described_class.classify(user: user, password: "wrong")).to eq("invalid_password")
    end

    it "returns 'other' when authenticate would succeed (escape hatch — should not normally fire)" do
      user = create(:user, status: "active")
      expect(described_class.classify(user: user, password: "SecurePassword123!")).to eq("other")
    end

    it "every produced code is in the documented REASONS allowlist" do
      # Sanity: don't drift the implementation away from the documented set.
      possible_outputs = %w[unknown_email no_local_password suspended invalid_password other]
      expect(possible_outputs - described_class::REASONS).to eq([])
    end
  end
end
