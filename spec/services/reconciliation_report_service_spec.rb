# frozen_string_literal: true

require "rails_helper"

# #911 layer 2 — the instance-wide report an operator reads before an upgrade
# lands on their users.
RSpec.describe ReconciliationReportService do
  let(:catalog) { create(:control_catalog) }
  let(:baseline) { create(:profile_document, control_catalog: catalog) }

  describe "what it reports" do
    it "is empty when every document can name its catalog" do
      create(:ssp_document, profile_document: baseline)

      expect(described_class.new.rows).to be_empty
      expect(described_class.new).not_to be_any
    end

    it "reports a document with no baseline" do
      ssp = create(:ssp_document, profile_document: nil, name: "Legacy SSP")
      create(:ssp_control, ssp_document: ssp, control_id: "ac-1")

      row = described_class.new.rows.find { _1.document == ssp }

      expect(row).to be_present
      expect(row.type_label).to eq("Ssp document").or eq(SspDocument.model_name.human)
      expect(row.codes).to include("missing_profile_source")
    end

    it "separates blocking from advisory" do
      blocking_ssp = create(:ssp_document, profile_document: nil)  # blocking
      create(:ssp_control, ssp_document: blocking_ssp, control_id: "ac-1")
      cdef = create(:cdef_document, profile_document: baseline)    # lineage fine
      cdef.cdef_controls.create!(stig_id: "SV-1r1_rule", rule_id: "SV-1r1_rule",
                                 title: "Unmapped", row_order: 0)

      report = described_class.new
      expect(report.blocking_count).to eq(1)
      expect(report.advisory_count).to eq(1)
      expect(report.total).to eq(2)
    end

    # An operator works down the list; the ones stopping people editing come
    # first.
    it "orders blocking rows before advisory ones" do
      cdef = create(:cdef_document, profile_document: baseline)
      cdef.cdef_controls.create!(stig_id: "SV-1r1_rule", rule_id: "SV-1r1_rule",
                                 title: "Unmapped", row_order: 0)
      blocking_ssp = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: blocking_ssp, control_id: "ac-1")

      expect(described_class.new.rows.first).to be_blocking
    end
  end

  # An earlier analysis of this exact data counted 36 SSPs where the app sees 2,
  # because soft-deleted `phase2-test-*` rows were included. A report that counts
  # deleted documents sends an operator to fix work that no longer exists.
  describe "soft-deleted documents" do
    it "excludes them" do
      deleted = create(:ssp_document, profile_document: nil, name: "Deleted SSP")
      create(:ssp_control, ssp_document: deleted, control_id: "ac-1")
      deleted.soft_delete!

      names = described_class.new.rows.map { _1.document.name }
      expect(names).not_to include("Deleted SSP")
    end

    it "does not count them in the per-type totals either" do
      gone = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: gone, control_id: "ac-1")
      gone.soft_delete!
      live = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: live, control_id: "ac-1")

      entry = described_class.new.summary.find { _1[:type] == SspDocument.model_name.human.pluralize }
      expect(entry[:total]).to eq(SspDocument.count)
      expect(described_class.new.rows.map(&:document)).to eq([ live ])
    end
  end

  # A denominator is what makes the numerator mean anything.
  describe "#summary" do
    it "reports affected against the total for every lineage-bearing type" do
      unresolved = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: unresolved, control_id: "ac-1")
      create(:ssp_document, profile_document: baseline)

      entry = described_class.new.summary.find { _1[:type] == SspDocument.model_name.human.pluralize }

      expect(entry[:affected]).to eq(1)
      expect(entry[:total]).to eq(2)
    end

    it "covers every document type that declares lineage" do
      covered = described_class::DOCUMENT_TYPES
      declaring = [ ProfileDocument, SspDocument, SapDocument, SarDocument, PoamDocument, CdefDocument ]

      expect(covered).to match_array(declaring),
        "a document type declaring lineage but missing here is invisible to operators"
    end
  end
end
