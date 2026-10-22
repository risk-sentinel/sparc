# frozen_string_literal: true

require "rails_helper"
require "digest"

# #1228 — the bundled Rev 5 catalog: NIST's XML vendored unchanged, the JSON
# generated from it and committed, and the provenance sidecar that describes
# both. These keep the three in agreement, and notice when NIST releases what
# the catalog currently takes from `develop`.
RSpec.describe NistCatalogSource do
  let(:provenance) { described_class.provenance }

  describe "the vendored XML" do
    it "is byte-for-byte the file the sidecar records" do
      bytes = described_class.xml_path.binread
      recorded = provenance.dig("files", described_class::XML)

      expect(Digest::SHA256.hexdigest(bytes)).to eq(recorded["sha256"])
      expect(bytes.bytesize).to eq(recorded["bytes"])
      expect(recorded["source_url"]).to include(provenance["source_commit"], provenance["source_path"])
    end

    it "is schema-valid OSCAL against the baked-in XSD" do
      result = OscalSchemaValidationService.validate_xml(:catalog, described_class.xml_path.read, version: "1.2.3")

      expect(result.errors).to be_empty
    end

    it "is NIST's catalog, metadata as NIST wrote it" do
      catalog = described_class.catalog["catalog"]

      expect(catalog["uuid"]).to eq(described_class::MAIN_1_2_3_UUID)
      expect(catalog.dig("metadata", "title")).to start_with("Electronic (OSCAL) Version of NIST SP 800-53 Rev 5")
      expect(catalog.to_json).not_to include("pre_release", "source_commit")
    end
  end

  describe "the generated JSON" do
    # Pattern: spec/lib/odp_worksheet_builder_spec.rb.
    it "matches what catalog:build_rev5 writes, byte for byte" do
      expect(described_class.json_path.read).to eq(described_class.render),
        "lib/data/catalogs/#{described_class::JSON_FILE} is stale; run bin/rails catalog:build_rev5"
    end

    it "was made by the converter version the sidecar records" do
      expect(provenance.dig("converter", "version")).to eq(OscalCatalogXmlToJson::VERSION)
    end

    it "is schema-valid OSCAL JSON" do
      expect(OscalSchemaValidationService.validate(:catalog, described_class.catalog, version: "1.2.3").errors).to be_empty
    end

    it "carries NIST's three unreleased fixes" do
      controls = described_class.catalog["catalog"]["groups"].flat_map { |g| g["controls"] }
                                .flat_map { |c| [ c, *Array(c["controls"]) ] }.index_by { |c| c["id"] }
      sa_15_13 = controls.fetch("sa-15.13")
      statement = sa_15_13["parts"].find { |p| p["name"] == "statement" }["prose"]
      sa_24_b = controls.fetch("sa-24")["parts"].find { |p| p["id"] == "sa-24_obj" }["parts"].find { |p| p["id"] == "sa-24_obj.b" }

      expect(statement).to include("{{ insert: param, sa-15.13_odp.01 }}")
      expect(statement).not_to include("personally identifiable information")
      expect(sa_24_b["parts"].map { |p| p["id"] }).to include("sa-24_obj.b-6", "sa-24_obj.b-10")
    end
  end

  describe "pre-release" do
    it "is flagged, from the sidecar" do
      expect(provenance["pre_release"]).to be(true)
      expect(described_class.pre_release?).to be(true)
      expect(provenance).to include("source_branch" => "main")
    end

    it "flags a catalog from either pre-release file, or one the data migration patched, and nothing else" do
      develop = build(:control_catalog, oscal_uuid: described_class::DEVELOP_UUID)
      main = build(:control_catalog, metadata_extra: { "catalog_uuid" => described_class::MAIN_1_2_3_UUID })
      patched = build(:control_catalog, oscal_uuid: described_class::RELEASED_V5_2_0_UUID,
                                        metadata_extra: { "nist_develop_patch" => { "commit" => "d56011a5" } })
      released = build(:control_catalog, oscal_uuid: described_class::RELEASED_V5_2_0_UUID)
      other = build(:control_catalog, oscal_uuid: SecureRandom.uuid)

      expect([ develop, main, patched, released, other ].map { |c| described_class.pre_release_catalog?(c) })
        .to eq([ true, true, true, false, false ])
    end

    it "flags nothing once the sidecar stops calling the source pre-release" do
      allow(described_class).to receive(:pre_release?).and_return(false)

      described_class::PRE_RELEASE_UUIDS.each do |uuid|
        expect(described_class.pre_release_catalog?(build(:control_catalog, oscal_uuid: uuid))).to be(false)
      end
    end
  end

  # The release check: against data RECORDED by `bin/rails catalog:check_nist_release`,
  # because the suite does not assume network access.
  describe "catching NIST's release" do
    let(:record) { JSON.parse(described_class.release_data_path.read) }

    it "has release data recorded for the pinned commit" do
      expect(record["recorded_at"]).to be_present,
        "no release data recorded; run bin/rails catalog:check_nist_release (needs gh) and commit what it writes"
      expect(record["fix_commit"]).to eq(provenance["source_commit"])
    end

    it "fails once a recorded NIST release carries the fixes, while the catalog is still pre-release" do
      action = described_class.releases_requiring_action(record)

      expect(action).to be_empty,
        "NIST release #{action.map { |r| r['tag'] }.join(', ')} postdates or carries the develop fixes: " \
        "replace the pre-release catalog with NIST's release and set pre_release to false"
    end

    describe ".releases_requiring_action" do
      let(:base) { { "fix_commit_date" => "2026-05-11T00:00:00Z" } }

      it "names a release that carries the commit" do
        record = base.merge("releases" => [ { "tag" => "v9.9.9", "published_at" => "2026-11-01T00:00:00Z", "contains_fix_commit" => true } ])
        expect(described_class.releases_requiring_action(record).map { |r| r["tag"] }).to eq([ "v9.9.9" ])
      end

      it "names an unchecked release published after the commit" do
        record = base.merge("releases" => [ { "tag" => "v9.9.8", "published_at" => "2026-06-01T00:00:00Z", "contains_fix_commit" => nil } ])
        expect(described_class.releases_requiring_action(record).size).to eq(1)
      end

      it "ignores a checked release that does not carry it, and an older one" do
        record = base.merge("releases" => [
          { "tag" => "v9.9.7", "published_at" => "2026-06-01T00:00:00Z", "contains_fix_commit" => false },
          { "tag" => "v1.4.0", "published_at" => "2025-08-26T00:00:00Z", "contains_fix_commit" => nil }
        ])
        expect(described_class.releases_requiring_action(record)).to be_empty
      end
    end
  end
end
