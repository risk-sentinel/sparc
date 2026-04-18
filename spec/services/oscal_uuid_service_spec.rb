require "rails_helper"

RSpec.describe OscalUuidService do
  describe ".derived" do
    it "is deterministic -- same inputs always produce the same UUID" do
      a = described_class.derived("sap-activity", "examine")
      b = described_class.derived("sap-activity", "examine")
      expect(a).to eq(b)
    end

    it "is order-sensitive -- different part order -> different UUID" do
      a = described_class.derived("sap-activity", "examine")
      b = described_class.derived("examine", "sap-activity")
      expect(a).not_to eq(b)
    end

    it "produces distinct UUIDs for distinct inputs" do
      uuids = 100.times.map { |i| described_class.derived("ssp-ir", i.to_s) }
      expect(uuids.uniq.size).to eq(100)
    end

    it "produces v4-shaped UUIDs that match BackMatterResource::UUID_V4_REGEX" do
      50.times do |i|
        uuid = described_class.derived("test", i.to_s)
        expect(uuid).to match(BackMatterResource::UUID_V4_REGEX)
      end
    end

    it "accepts heterogeneous part types (strings, integers, UUIDs)" do
      uuid = described_class.derived(SecureRandom.uuid, "ssp-statement", 42, "ac-1_smt.a")
      expect(uuid).to match(BackMatterResource::UUID_V4_REGEX)
    end

    it "raises when called with no parts" do
      expect { described_class.derived }.to raise_error(ArgumentError, /at least one part/)
    end

    it "NAMESPACE is a frozen v4 UUID" do
      expect(described_class::NAMESPACE).to be_frozen
      expect(described_class::NAMESPACE).to match(BackMatterResource::UUID_V4_REGEX)
    end
  end

  describe ".org_party_uuid_for" do
    it "returns the linked organization's stored UUID when document -> boundary -> org chain is intact" do
      org = create(:organization)
      boundary = create(:authorization_boundary, organization: org)
      document = create(:sap_document, authorization_boundary: boundary)
      expect(described_class.org_party_uuid_for(document)).to eq(org.uuid)
    end

    it "falls back to a deterministic derived UUID when no boundary is linked" do
      document = create(:sap_document, authorization_boundary: nil)
      result = described_class.org_party_uuid_for(document)
      expect(result).to match(BackMatterResource::UUID_V4_REGEX)
      # Same document -> same fallback UUID across calls.
      expect(described_class.org_party_uuid_for(document)).to eq(result)
    end

    it "falls back when boundary exists but has no organization" do
      boundary = create(:authorization_boundary, organization: nil)
      document = create(:sap_document, authorization_boundary: boundary)
      result = described_class.org_party_uuid_for(document)
      expect(result).to match(BackMatterResource::UUID_V4_REGEX)
      expect(result).not_to eq(described_class.org_party_uuid_for(create(:sap_document)))
    end
  end
end
