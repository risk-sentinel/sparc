# frozen_string_literal: true

require "rails_helper"

# #968 item 4 — a "best-effort" step must still leave a trace.
#
# `CatalogImportService` treats the parts backfill as best-effort: a parts failure
# must not fail an otherwise good catalog import, since the migration backfill can
# re-run later. That decision is sound and is kept.
#
# What was wrong is that the failure went only to `Rails.logger`. The catalog
# imported as clean while control guidance parts were missing, and the gap
# surfaced only when somebody noticed parts absent from a control page — the same
# shape as item 3's finding on the CDEF side.
#
# Both directions are asserted. A marker written unconditionally would flag every
# catalog and be worse than none.
RSpec.describe CatalogImportService, "parts backfill leaves a trace (#968 item 4)" do
  let(:catalog) { create(:control_catalog) }
  # `call` is never invoked here — the contract under test is the best-effort
  # step itself, not a whole file import.
  let(:service) { described_class.allocate }

  context "when the extractor fails" do
    before do
      allow(CatalogPartExtractorService)
        .to receive(:backfill_catalog_parts!).and_raise(ArgumentError, "extractor exploded")
    end

    it "records the failure on the catalog instead of only logging it" do
      expect(catalog.metadata_extra.to_h["catalog_parts_backfill_failed_at"]).to be_nil

      service.send(:backfill_parts_best_effort, catalog)

      catalog.reload
      expect(catalog.metadata_extra["catalog_parts_backfill_failed_at"]).to be_present
      expect(catalog.metadata_extra["catalog_parts_backfill_error"]).to include("extractor exploded")
    end

    it "does not raise — the import must survive a parts failure" do
      expect { service.send(:backfill_parts_best_effort, catalog) }.not_to raise_error
      expect(service.send(:backfill_parts_best_effort, catalog)).to be(false)
    end
  end

  context "when the extractor succeeds" do
    before do
      allow(CatalogPartExtractorService).to receive(:backfill_catalog_parts!).and_return(true)
    end

    it "leaves no failure marker" do
      expect(service.send(:backfill_parts_best_effort, catalog)).to be(true)

      expect(catalog.reload.metadata_extra.to_h["catalog_parts_backfill_failed_at"]).to be_nil
    end
  end
end
