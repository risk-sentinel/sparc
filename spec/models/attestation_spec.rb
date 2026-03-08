require "rails_helper"

RSpec.describe Attestation, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:attester_name) }
    it { is_expected.to validate_presence_of(:statement) }
    it { is_expected.to validate_presence_of(:attested_at) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:evidence) }
  end

  describe "ROLES" do
    it "includes all expected roles" do
      expect(Attestation::ROLES).to contain_exactly(
        "control_owner", "system_owner", "isso", "ciso", "assessor", "authorizing_official"
      )
    end
  end

  describe "#role_label" do
    it "returns human-readable label for known role" do
      attestation = build(:attestation, role: "isso")
      expect(attestation.role_label).to eq("ISSO")
    end

    it "returns titleized role for unknown role" do
      attestation = build(:attestation, role: "custom_role")
      expect(attestation.role_label).to eq("Custom Role")
    end

    it "returns Unknown for nil role" do
      attestation = build(:attestation, role: nil)
      expect(attestation.role_label).to eq("Unknown")
    end
  end

  describe "#generate_signature!" do
    it "generates a SHA-256 signature hash" do
      attestation = create(:attestation)
      attestation.generate_signature!

      expect(attestation.signature_hash).to be_present
      expect(attestation.signature_hash.length).to eq(64)
    end

    it "produces consistent hashes for the same data" do
      attestation = create(:attestation)
      attestation.generate_signature!
      first_hash = attestation.signature_hash

      attestation.generate_signature!
      expect(attestation.signature_hash).to eq(first_hash)
    end
  end
end
