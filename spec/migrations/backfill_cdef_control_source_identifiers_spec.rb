# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260808120100_backfill_cdef_control_source_identifiers.rb")

# #912 — moving each existing CDEF control's identifier into `source_control_id`
# without inventing NIST references.
#
# The migration is deferred, so this drives `backfill_source_identifiers`
# directly rather than through `up` (which would only enqueue it).
RSpec.describe BackfillCdefControlSourceIdentifiers do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  # Reproduce the PRE-migration state faithfully. Creating through the model
  # would canonicalise `control_id` on write (#912 re-enabled that), so `IAM.3`
  # would already be `iam.3` and the backfill would look correct for the wrong
  # reason. Real rows predate the callback and still hold their original casing,
  # so the raw value is written directly.
  def control_for(document, control_id: nil, **attrs)
    control = CdefControl.create!(cdef_document: document, title: "x", row_order: 0, **attrs)
    control.update_columns(control_id: control_id) if control_id
    control
  end

  describe "vocabulary inferred from the document, not the identifier's shape" do
    it "labels an AWS Labs CDEF as aws_security_hub" do
      doc = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })
      control = control_for(doc, control_id: "IAM.3")

      migration.backfill_source_identifiers

      expect(control.reload.source_vocabulary).to eq("aws_security_hub")
      expect(control.source_control_id).to eq("IAM.3")
    end

    it "labels a DISA STIG document as disa_stig" do
      doc = create(:cdef_document, cdef_type: "disa_stig")
      control = control_for(doc, stig_id: "SV-1r1_rule", control_id: "ac-2")

      migration.backfill_source_identifiers

      expect(control.reload.source_vocabulary).to eq("disa_stig")
      expect(control.source_control_id).to eq("SV-1r1_rule")
    end

    it "labels anything else as nist" do
      doc = create(:cdef_document, cdef_type: "custom")
      control = control_for(doc, control_id: "ac-2")

      migration.backfill_source_identifiers

      expect(control.reload.source_vocabulary).to eq("nist")
    end
  end

  # It must not guess a NIST control from a Security Hub id — that is the
  # unverifiable inference the whole issue exists to remove.
  describe "what it does with control_id" do
    it "clears a non-NIST identifier out of the NIST column" do
      doc = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })
      control = control_for(doc, control_id: "IAM.3")

      migration.backfill_source_identifiers

      expect(control.reload.control_id).to be_nil
      expect(control.source_control_id).to eq("IAM.3"), "provenance is kept, not discarded"
    end

    it "leaves a NIST document's control_id alone" do
      doc = create(:cdef_document, cdef_type: "custom")
      control = control_for(doc, control_id: "ac-2")

      migration.backfill_source_identifiers

      expect(control.reload.control_id).to eq("ac-2")
    end

    # A STIG row's control_id already holds NIST resolved through CCI (#911),
    # and its source is the rule id — so nothing should be cleared.
    it "keeps a STIG row's resolved NIST reference" do
      doc = create(:cdef_document, cdef_type: "disa_stig")
      control = control_for(doc, stig_id: "SV-1r1_rule", control_id: "ac-2")

      migration.backfill_source_identifiers

      expect(control.reload.control_id).to eq("ac-2")
    end
  end

  # Running twice must not turn an already-resolved NIST id into the "source".
  describe "idempotency and resume-from-partial" do
    it "is a no-op on a second run" do
      doc = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })
      control = control_for(doc, control_id: "IAM.3")

      migration.backfill_source_identifiers
      after_first = control.reload.attributes.slice("source_control_id", "source_vocabulary", "control_id")

      migration.backfill_source_identifiers

      expect(control.reload.attributes.slice("source_control_id", "source_vocabulary", "control_id"))
        .to eq(after_first)
    end

    it "skips a row already migrated and still processes its neighbours" do
      doc = create(:cdef_document, cdef_type: "disa_stig")
      done = control_for(doc, stig_id: "SV-1r1_rule", source_control_id: "ALREADY", source_vocabulary: "nist")
      pending_row = CdefControl.create!(cdef_document: doc, stig_id: "SV-2r1_rule", title: "y", row_order: 1)

      migration.backfill_source_identifiers

      expect(done.reload.source_control_id).to eq("ALREADY"), "an already-migrated row is left alone"
      expect(pending_row.reload.source_control_id).to eq("SV-2r1_rule")
    end
  end

  it "does not strand controls belonging to soft-deleted documents" do
    doc = create(:cdef_document, cdef_type: "disa_stig")
    control = control_for(doc, stig_id: "SV-9r1_rule")
    doc.soft_delete!

    migration.backfill_source_identifiers

    expect(control.reload.source_control_id).to eq("SV-9r1_rule")
  end
end
