# frozen_string_literal: true

require "rails_helper"

# #911 — the bulk-insert path must canonicalise control identifiers.
#
# `ControlIdentifiable` hangs canonicalisation off `before_validation`, which
# covers a UI edit or an API PATCH and misses the path that creates almost every
# row: all nine parser services insert through `batch_insert_records`, which
# calls `activerecord-import` with `validate: false`. That runs no callbacks, so
# the concern alone left imports untouched — and imports are where the malformed
# data came from (`SarControl` measured 0% resolvable verbatim, every one of
# those rows written by `sar_excel_parser_service`).
#
# These examples fail against a `batch_insert_records` that does not
# canonicalise, which is the whole point of having them.
RSpec.describe BatchInsertable do
  # A minimal host, so the concern is tested rather than one parser's fixtures.
  let(:host_class) do
    Class.new do
      include BatchInsertable

      def initialize(document) = @document = document

      def insert(control_attrs)
        batch_insert_records(
          control_class: SspControl,
          field_class:   SspControlField,
          document_fk:   :ssp_document_id,
          control_attrs: control_attrs,
          field_entries: []
        )
      end
    end
  end

  let(:document) { create(:ssp_document) }
  let(:service)  { host_class.new(document) }

  def stored_control_ids
    SspControl.where(ssp_document_id: document.id).order(:row_order).pluck(:control_id)
  end

  it "canonicalises the padded form SPARC displays" do
    service.insert([ { control_id: "AC-02", title: "Account Management", row_order: 0 } ])

    expect(stored_control_ids).to eq([ "ac-2" ])
  end

  it "canonicalises the NIST publication form" do
    service.insert([ { control_id: "AC-2 (1)", title: "Automated System Account Management", row_order: 0 } ])

    expect(stored_control_ids).to eq([ "ac-2.1" ])
  end

  it "stores one identifier for spellings of the same control" do
    # The defect in one line: these are the same control, and a literal join
    # against a table holding all three finds at most one of them.
    service.insert([
      { control_id: "AC-02",    title: "a", row_order: 0 },
      { control_id: "ac-2",     title: "b", row_order: 1 },
      { control_id: "AC-2",     title: "c", row_order: 2 }
    ])

    expect(stored_control_ids.uniq).to eq([ "ac-2" ])
  end

  it "leaves a blank identifier blank" do
    # Shared-responsibility rows legitimately carry no control id.
    service.insert([ { control_id: nil, title: "Cloud Provider — Network Bound", row_order: 0 } ])

    expect(stored_control_ids).to eq([ nil ])
  end

  it "keeps an unparseable identifier rather than storing 'unknown'" do
    service.insert([ { control_id: "???", title: "x", row_order: 0 } ])

    expect(stored_control_ids).not_to eq([ "unknown" ])
  end

  it "agrees with the callback path on the same input" do
    # The two writers must not drift — that divergence is #852's failure mode,
    # and a bulk writer with its own normaliser is how it comes back.
    # Separate documents, because SspControl enforces one row per control.
    service.insert([ { control_id: "AC-02 (1)", title: "x", row_order: 0 } ])
    saved = SspControl.create!(ssp_document: create(:ssp_document),
                               control_id: "AC-02 (1)", title: "y", row_order: 0)

    expect(stored_control_ids.first).to eq(saved.reload.control_id)
  end

  it "does not canonicalise a model that has not asked for it" do
    # The hook is opt-in via `canonicalises_control_id`; it must not reach into
    # arbitrary columns of models that never declared one.
    expect(SspControlField.respond_to?(:canonicalise_control_ids!)).to be(false)
  end
end
