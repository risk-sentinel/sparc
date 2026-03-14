require "rails_helper"

RSpec.describe OscalMetadata do
  describe "included in SspDocument" do
    let(:ssp) { create(:ssp_document) }

    it "has OSCAL_VERSION constant" do
      expect(OscalMetadata::OSCAL_VERSION).to eq("1.1.2")
    end

    it "provides build_oscal_metadata" do
      metadata = ssp.build_oscal_metadata
      expect(metadata).to be_a(Hash)
      expect(metadata["title"]).to eq(ssp.name)
      expect(metadata["oscal-version"]).to eq("1.1.2")
    end

    it "provides oscal_roles accessor" do
      expect(ssp).to respond_to(:oscal_roles)
      expect(ssp).to respond_to(:oscal_roles=)
    end

    it "provides oscal_parties accessor" do
      expect(ssp).to respond_to(:oscal_parties)
    end
  end
end
