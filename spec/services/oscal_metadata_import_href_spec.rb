require "rails_helper"

RSpec.describe OscalMetadata, ".resolve_import_href + .import_href_for (#395 P2)" do
  describe ".resolve_import_href" do
    let(:ssp) { create(:ssp_document) }

    it "returns the document when href is `uuid:<...>` and matches" do
      result = described_class.resolve_import_href("uuid:#{ssp.uuid}", SspDocument)
      expect(result).to eq(ssp)
    end

    it "returns nil when href is blank" do
      expect(described_class.resolve_import_href(nil, SspDocument)).to be_nil
      expect(described_class.resolve_import_href("",  SspDocument)).to be_nil
    end

    it "returns nil when href is a `#anchor` placeholder" do
      expect(described_class.resolve_import_href("#system-security-plan", SspDocument)).to be_nil
    end

    it "returns nil when uuid doesn't match any document" do
      expect(described_class.resolve_import_href("uuid:00000000-0000-4000-8000-000000000000", SspDocument)).to be_nil
    end
  end

  describe ".import_href_for" do
    it "returns `uuid:<sibling.uuid>` for a present sibling" do
      ssp = create(:ssp_document)
      expect(described_class.import_href_for(ssp)).to eq("uuid:#{ssp.uuid}")
    end

    it "returns nil for nil sibling (so caller can fall back to '#')" do
      expect(described_class.import_href_for(nil)).to be_nil
    end
  end
end
