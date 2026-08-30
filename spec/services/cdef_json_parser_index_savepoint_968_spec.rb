# frozen_string_literal: true

require "rails_helper"
require "tempfile"

# #968 — the #963 audit at the CDEF import choke point.
#
# `CdefJsonParserService#parse` runs inside `CdefMutationService.apply`, which
# wraps the whole mutation in a database transaction. `index_components` rescues
# StandardError, and `CdefComponentIndexer#index!` ends in
# `CdefComponent.insert_all!` — a bulk INSERT against a unique index on
# (cdef_document_id, component_uuid). `index!` opens its own
# `CdefComponent.transaction`, but WITHOUT `requires_new` that joins the outer
# transaction instead of isolating it.
#
# So a CDEF carrying two components with the same uuid does not degrade one
# browser row: Postgres aborts the transaction on the failed statement, the
# rescue swallows it, and the whole import is lost while the caller reports
# success.
#
# THE FAILURE MUST BE REAL. An earlier version of this spec stubbed `index!` to
# `raise ActiveRecord::RecordNotUnique` and passed with the savepoint REMOVED —
# raising a Ruby exception object does not abort a Postgres transaction; only a
# failed statement does. The duplicate uuid below produces the actual violation.
RSpec.describe CdefJsonParserService, "component-index savepoint (#968)" do
  let(:document) { create(:cdef_document, name: "savepoint probe", status: "processing") }
  let(:shared_uuid) { "22222222-2222-4222-8222-00000000dupe" }

  # Two components, one uuid — violates idx_cdef_components_doc_uuid inside the
  # single `insert_all!` statement.
  let(:payload) do
    base = JSON.parse(Rails.root.join("spec/fixtures/files/components/aws_labs/s3-cd-v1.0.0.json").read)
    component = base["component-definition"]["components"].first
    twin = Marshal.load(Marshal.dump(component))
    component["uuid"] = shared_uuid
    twin["uuid"]      = shared_uuid
    twin["title"]     = "#{component['title']} (duplicate uuid)"
    base["component-definition"]["components"] = [ component, twin ]
    base
  end

  def parse_payload
    Tempfile.create([ "cdef", ".json" ]) do |f|
      f.write(JSON.generate(payload)); f.flush
      described_class.new(document, f.path).parse
    end
  end

  it "still imports the CDEF when component indexing hits a real DB constraint" do
    expect { parse_payload }.not_to raise_error

    expect(document.reload.cdef_controls.count).to be > 0,
      "the CDEF imported no controls — the component-index rescue poisoned the " \
      "transaction it runs inside (#963/#968)"
  end

  it "leaves the connection usable rather than in a failed transaction" do
    parse_payload

    # InFailedSqlTransaction surfaces on the NEXT statement, not at the rescue,
    # which is why "no exception was raised" is not sufficient evidence.
    expect { CdefDocument.count }.not_to raise_error
  end
end

# #968 item 3 — the partial-success contract.
#
# A swallow that only writes a log line makes a degraded import
# indistinguishable from a clean one: the document is marked completed either
# way. These pin the fact that a failed index is now RECORDED where an operator
# can see it.
RSpec.describe CdefJsonParserService, "partial-success contract (#968)" do
  let(:document) { create(:cdef_document, name: "degradation probe", status: "processing") }
  let(:fixture)  { Rails.root.join("spec/fixtures/files/components/aws_labs/s3-cd-v1.0.0.json") }

  context "when the component index fails" do
    before do
      allow_any_instance_of(CdefComponentIndexer).to receive(:index!)
        .and_raise(StandardError, "indexer exploded")
    end

    it "records the degradation on the document rather than only in the log" do
      described_class.new(document, fixture.to_s).parse

      meta = document.reload.import_metadata
      expect(meta["component_index_failed_at"]).to be_present,
        "a degraded import is indistinguishable from a clean one — nothing an " \
        "operator looks at says the component browser is missing rows (#968)"
      expect(meta["component_index_error"]).to include("indexer exploded")
    end

    it "still completes the import — the swallow stays deliberate" do
      expect { described_class.new(document, fixture.to_s).parse }.not_to raise_error
      expect(document.reload.cdef_controls.count).to be > 0
    end
  end

  context "when indexing succeeds" do
    it "leaves no degradation marker" do
      described_class.new(document, fixture.to_s).parse

      expect(document.reload.import_metadata["component_index_failed_at"]).to be_nil
    end
  end
end
