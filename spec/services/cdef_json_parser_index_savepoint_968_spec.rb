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
