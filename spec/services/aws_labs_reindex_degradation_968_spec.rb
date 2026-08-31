# frozen_string_literal: true

require "rails_helper"

# #968 item 4 — the judgement pass over the remaining swallows.
#
# `AwsLabsCdefImportService#reindex_components` rescues broadly so a failed
# component index cannot lose a document the refresh otherwise imported cleanly.
# That decision is right. What was wrong is that it recorded ONLY a log line,
# while the upload path (CdefJsonParserService) writes a marker that item 3 now
# surfaces in the API and on both screens.
#
# The consequence was silent and route-specific: an AWS Labs document whose index
# failed would report as a clean import everywhere, with the new badge dark,
# purely because it arrived through the refresh instead of an upload.
#
# Asserted in BOTH directions — a failure marks the document, a success leaves it
# alone. A writer that marked unconditionally would make every refreshed document
# look degraded.
RSpec.describe AwsLabsCdefImportService, "reindex degradation is recorded (#968 item 4)" do
  let(:document) { create(:cdef_document) }
  let(:content)  { { "component-definition" => { "components" => [] } } }
  let(:service)  { described_class.new }

  context "when the component indexer fails" do
    before do
      indexer = instance_double(CdefComponentIndexer)
      allow(CdefComponentIndexer).to receive(:new).and_return(indexer)
      allow(indexer).to receive(:index!).and_raise(ActiveRecord::StatementInvalid, "boom")
    end

    it "marks the document degraded instead of only logging" do
      expect(document.reload).not_to be_component_index_degraded

      service.send(:reindex_components, document, content)

      expect(document.reload).to be_component_index_degraded
      expect(document.import_metadata["component_index_error"]).to include("StatementInvalid")
    end

    it "does not raise — a failed index must not lose the imported document" do
      expect { service.send(:reindex_components, document, content) }.not_to raise_error
    end
  end

  context "when the component indexer succeeds" do
    before do
      indexer = instance_double(CdefComponentIndexer)
      allow(CdefComponentIndexer).to receive(:new).and_return(indexer)
      allow(indexer).to receive(:index!).and_return(true)
    end

    it "leaves the document unmarked" do
      service.send(:reindex_components, document, content)

      expect(document.reload).not_to be_component_index_degraded
      expect(document.import_metadata["component_index_failed_at"]).to be_nil
    end
  end
end
