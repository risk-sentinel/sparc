# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260821180000_reduce_statement_control_ids_on_cdef_controls")

# #1030 — the backfill for rows ingested before the parsers reduced at the
# resolution boundary.
RSpec.describe ReduceStatementControlIdsOnCdefControls do
  subject(:migration) { described_class.new }

  let(:document) { create(:cdef_document) }

  def control_with_nist_field(control_id, nist_reference)
    create(:cdef_control, cdef_document: document, control_id: control_id).tap do |c|
      create(:cdef_control_field, cdef_control: c,
                                  field_name: "nist_controls", field_value: nist_reference)
    end
  end

  before { migration.verbose = false }

  it "reduces a statement reference to the control it belongs to" do
    control = control_with_nist_field("cm-6-b", "cm-6-b")

    migration.up

    expect(control.reload.control_id).to eq("cm-6")
  end

  it "keeps an enhancement, which the catalog does hold" do
    control = control_with_nist_field("ia-5.1.a", "ia-5.1.a")

    migration.up

    expect(control.reload.control_id).to eq("ia-5.1")
  end

  it "leaves an already-addressable id alone" do
    control = control_with_nist_field("ac-2", "ac-2")

    expect { migration.up }.not_to(change { control.reload.control_id })
  end

  # The scoping rule. A plain InSpec CDEF keeps the source profile's own control
  # name in control_id, and a blanket reduction would truncate one shaped like a
  # NIST id. The `nist_controls` field is the marker that the id IS a NIST
  # reference.
  it "does not touch a row whose id did not come from NIST resolution" do
    control = create(:cdef_control, cdef_document: document, control_id: "abc-123-def")

    expect { migration.up }.not_to(change { control.reload.control_id })
  end

  it "leaves the statement detail in nist_controls where it already lives" do
    control = control_with_nist_field("cm-6-b", "cm-6-b")

    migration.up

    field = control.reload.cdef_control_fields.find_by(field_name: "nist_controls")
    expect(field.field_value).to eq("cm-6-b")
  end

  # #1030 / data-migration idempotency: a second run must be a no-op, and a run
  # that resumes after a partial pass must not corrupt the rows already done.
  it "is idempotent" do
    control = control_with_nist_field("pm-14-a-1", "pm-14-a-1")

    migration.up
    expect { migration.up }.not_to(change { control.reload.control_id })
    expect(control.reload.control_id).to eq("pm-14")
  end

  it "completes a partial run without disturbing the rows already reduced" do
    done    = control_with_nist_field("cm-6", "cm-6-b")   # already reduced
    pending = control_with_nist_field("ac-7-a", "ac-7-a")

    migration.up

    expect(done.reload.control_id).to eq("cm-6")
    expect(pending.reload.control_id).to eq("ac-7")
  end

  it "cannot be rolled back, because the reduced form does not carry the original" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
