# frozen_string_literal: true

require "rails_helper"

# #1106 — a prop with no `ns` CLAIMS NIST defined it. These specs pin the two
# behaviours that make that claim safe to rely on.
RSpec.describe OscalNamespace do
  describe ".uri" do
    it "resolves the namespaces SPARC emits into" do
      expect(described_class.uri(:cci)).to eq("http://cyber.mil/cci")
      expect(described_class.uri(:stig)).to eq("https://public.cyber.mil/stigs/")
      expect(described_class.uri(:sparc)).to eq("https://sparc.risk-sentinel.org/ns")
    end

    # The whole point of raising. A nil `ns` serialises as NIST's namespace, so a
    # typo'd key would silently convert a namespaced prop into a false claim on
    # NIST — the exact defect this class exists to remove. Returning nil here
    # would make the bug invisible; raising makes it a test failure.
    it "raises on an unknown key rather than returning nil" do
      expect { described_class.uri(:disa) }
        .to raise_error(described_class::UnknownNamespace, /unknown OSCAL namespace/)
    end

    it "never resolves to the mDNS-reserved sparc.local (RFC 6762)" do
      expect(described_class::REGISTRY.values.grep(/sparc\.local/)).to be_empty
    end
  end

  describe ".nist?" do
    it "treats a missing ns as NIST's, because OSCAL says so" do
      expect(described_class.nist?(nil)).to be true
      expect(described_class.nist?("")).to be true
      expect(described_class.nist?(described_class::OSCAL)).to be true
    end

    it "does not treat another authority as NIST" do
      expect(described_class.nist?(described_class.uri(:fedramp))).to be false
      expect(described_class.nist?(described_class.uri(:sparc))).to be false
    end
  end

  describe ".instance" do
    it "defaults to SPARC's own vocabulary" do
      expect(described_class.instance).to eq(described_class.uri(:sparc))
    end

    it "is the deployment's own namespace when the operator sets one" do
      allow(SparcConfig).to receive(:oscal_namespace).and_return("https://att.example/ns/oscal")

      expect(described_class.instance).to eq("https://att.example/ns/oscal")
      expect(described_class.known?("https://att.example/ns/oscal")).to be true
    end
  end
  # #1155 — both values are hashed inputs to every object identity in the
  # federation, so these assertions exist to make an accidental change LOUD.
  describe "the federation namespace UUID (#1155)" do
    it "is the UUIDv5 derived from SPARC's namespace URI, recomputed not repeated" do
      expect(described_class::FEDERATION_NAMESPACE)
        .to eq(described_class.derived_federation_namespace)
    end

    it "pins the exact registered value, so the URI cannot move silently either" do
      expect(described_class::FEDERATION_NAMESPACE).to eq("9f434272-f796-589b-b972-954790395630")
      expect(described_class.uri(:sparc)).to eq("https://sparc.risk-sentinel.org/ns")
    end

    it "derives from the FEDERATION namespace, never the operator's local vocabulary" do
      allow(SparcConfig).to receive(:oscal_namespace).and_return("https://att.example/ns/oscal")

      expect(described_class.derived_federation_namespace)
        .to eq("9f434272-f796-589b-b972-954790395630")
    end

    it "is a syntactically valid UUID" do
      expect(described_class::FEDERATION_NAMESPACE)
        .to match(/\A\h{8}-\h{4}-5\h{3}-[89ab]\h{3}-\h{12}\z/)
    end

    it "changes when the namespace URI changes, which is why the pin above matters" do
      other = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "https://risk-sentinel.org/ns/sparc")

      expect(other).not_to eq(described_class::FEDERATION_NAMESPACE)
    end
  end
end
