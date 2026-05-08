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

  # #451: anything stored in metadata_extra that isn't an OSCAL spec field
  # must NOT leak into the export — internal SPARC bookkeeping
  # (ProgressTrackable's processing_stage, processing_message,
  # processing_*_at, import_warnings, etc.) was crashing schema validation.
  describe "metadata_extra allowlist (#451)" do
    let(:ssp) do
      create(:ssp_document, metadata_extra: {
        # OSCAL spec keys — should pass through
        "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
        "props" => [ { "name" => "marking", "value" => "CUI" } ],
        "remarks" => "All good.",
        # Internal SPARC bookkeeping — must be filtered
        "processing_stage" => "complete",
        "processing_message" => "Imported 100 controls",
        "processing_started_at" => Time.current.iso8601,
        "processing_completed_at" => Time.current.iso8601,
        "import_warnings" => [ "missing X" ],
        "import_warnings_summary" => "1 warning",
        "import_warnings_acknowledged" => false,
        # Random extra field — also filtered
        "internal_debug_blob" => { "a" => 1 }
      })
    end

    it "passes through every key in METADATA_EXTRA_KEYS" do
      metadata = ssp.build_oscal_metadata
      expect(metadata["roles"]).to eq([ { "id" => "prepared-by", "title" => "Prepared By" } ])
      expect(metadata["props"]).to eq([ { "name" => "marking", "value" => "CUI" } ])
      expect(metadata["remarks"]).to eq("All good.")
    end

    it "strips every key NOT in METADATA_EXTRA_KEYS" do
      metadata = ssp.build_oscal_metadata
      filtered = %w[
        processing_stage processing_message processing_started_at
        processing_completed_at import_warnings import_warnings_summary
        import_warnings_acknowledged internal_debug_blob
      ]
      filtered.each do |key|
        expect(metadata).not_to have_key(key), "expected #{key} to be filtered out of OSCAL metadata"
      end
    end

    it "leaves base OSCAL fields intact" do
      metadata = ssp.build_oscal_metadata
      expect(metadata).to include("title", "version", "oscal-version", "last-modified")
    end

    it "covers every document type that includes the concern" do
      [
        :cdef_document, :ssp_document, :sar_document, :poam_document,
        :profile_document, :control_catalog
      ].each do |factory|
        doc = create(factory, metadata_extra: { "processing_stage" => "x", "remarks" => "ok" })
        metadata = doc.build_oscal_metadata
        expect(metadata).not_to have_key("processing_stage"), "leak in #{factory}"
        expect(metadata["remarks"]).to eq("ok"), "allowlist broken in #{factory}"
      end
    end
  end
end
