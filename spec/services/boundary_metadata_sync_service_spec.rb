require "rails_helper"

RSpec.describe BoundaryMetadataSyncService do
  let(:boundary) do
    create(:authorization_boundary,
           boundary_metadata: {
             "system_title"   => "Acme Production",
             "impact_level"   => "MODERATE",
             "system_owner"   => { "name" => "Alice" }
           })
  end

  let!(:ssp) { create(:ssp_document, authorization_boundary: boundary, name: "Old Name") }

  describe "#propagate!" do
    it "writes boundary metadata onto each linked document" do
      result = described_class.new(boundary).propagate!
      expect(result.values.sum).to be >= 1
      ssp.reload
      expect(ssp.name).to eq("Acme Production")
    end

    it "is idempotent (no writes on second run)" do
      described_class.new(boundary).propagate!
      result = described_class.new(boundary).propagate!
      expect(result.values.sum).to eq(0)
    end

    it "skips fields that the document doesn't have setters for" do
      # SspDocument doesn't have :isso_data= today; should not raise.
      boundary.update!(boundary_metadata: boundary.boundary_metadata.merge("isso" => { "name" => "Bob" }))
      expect { described_class.new(boundary).propagate! }.not_to raise_error
    end
  end

  describe "#drift_for" do
    it "reports differences after a manual document edit" do
      described_class.new(boundary).propagate!
      ssp.update!(name: "Drifted")
      drift = described_class.new(boundary).drift_for(ssp)
      expect(drift).to have_key("system_title")
      expect(drift["system_title"][:boundary]).to eq("Acme Production")
      expect(drift["system_title"][:document]).to eq("Drifted")
    end

    it "returns empty when in sync" do
      described_class.new(boundary).propagate!
      expect(described_class.new(boundary).drift_for(ssp.reload)).to be_empty
    end
  end

  describe "#status_for" do
    it "returns :missing_fk when document has no boundary FK" do
      orphan = create(:ssp_document, authorization_boundary: nil)
      expect(described_class.new(boundary).status_for(orphan)).to eq(:missing_fk)
    end

    it "returns :in_sync after propagate" do
      described_class.new(boundary).propagate!
      expect(described_class.new(boundary).status_for(ssp.reload)).to eq(:in_sync)
    end

    it "returns :drift when fields differ" do
      described_class.new(boundary).propagate!
      ssp.update!(name: "Drifted")
      expect(described_class.new(boundary).status_for(ssp.reload)).to eq(:drift)
    end
  end
end
