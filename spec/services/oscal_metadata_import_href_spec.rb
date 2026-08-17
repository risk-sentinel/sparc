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

    # #946 — SPARC writes `uuid:<...>`, so that was the only form understood.
    # Every other producer writes something else, and against those the resolver
    # returned nil silently and the document never reached its baseline.
    describe "href forms other producers actually write (#946)" do
      it "resolves an OSCAL `#<uuid>` fragment reference" do
        expect(described_class.resolve_import_href("##{ssp.uuid}", SspDocument)).to eq(ssp)
      end

      it "resolves a bare uuid" do
        expect(described_class.resolve_import_href(ssp.uuid, SspDocument)).to eq(ssp)
      end

      it "resolves a uuid embedded in a filename" do
        expect(described_class.resolve_import_href("./ssp-#{ssp.uuid}.json", SspDocument)).to eq(ssp)
      end

      it "resolves a uuid in a URL" do
        expect(described_class.resolve_import_href("https://example.gov/oscal/#{ssp.uuid}", SspDocument))
          .to eq(ssp)
      end

      # Matching a UUID is identity. Matching a NAME would be inventing a
      # lineage claim nobody made — the inference #911 forbids.
      it "refuses to match by filename when the href carries no uuid" do
        ssp.update!(name: "NIST_SP-800-53_rev5_LOW-baseline")

        expect(described_class.resolve_import_href("NIST_SP-800-53_rev5_LOW-baseline.json", SspDocument))
          .to be_nil
      end

      it "does not resolve a uuid belonging to a different class" do
        profile = create(:profile_document)

        expect(described_class.resolve_import_href("uuid:#{profile.uuid}", SspDocument)).to be_nil
      end
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
