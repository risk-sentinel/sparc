# frozen_string_literal: true

require "rails_helper"

# #912 — the source identifier and the NIST reference are different things and
# now live in different columns.
#
# `cdef_controls.control_id` used to hold whichever the importer happened to
# have: an AWS Security Hub id (`IAM.3`), a STIG rule resolved through CCI, an
# InSpec control name, or NIST. One column, four vocabularies, and nothing could
# tell them apart — which is why #911 had to disable canonicalisation on this
# model entirely.
RSpec.describe "CdefControl source identifier (#912)", type: :model do
  let(:document) { create(:cdef_document) }

  describe "the two columns" do
    it "canonicalises the NIST reference" do
      control = document.cdef_controls.create!(control_id: "AC-02 (1)", title: "x", row_order: 0)

      expect(control.reload.control_id).to eq("ac-2.1")
    end

    # The whole point of the split: this is the value #911 could not protect.
    it "never rewrites the source identifier" do
      control = document.cdef_controls.create!(
        source_control_id: "IAM.3", source_vocabulary: "aws_security_hub",
        control_id: "AC-02", title: "x", row_order: 0
      )

      expect(control.reload.source_control_id).to eq("IAM.3")
    end

    it "leaves a FedRAMP KSI identifier's significant padding alone" do
      control = document.cdef_controls.create!(
        source_control_id: "ksi-auth-01", source_vocabulary: "fedramp_ksi",
        title: "x", row_order: 0
      )

      expect(control.reload.source_control_id).to eq("ksi-auth-01")
    end
  end

  describe "source_vocabulary" do
    it "accepts every framework SPARC ingests" do
      CdefControl::SOURCE_VOCABULARIES.each do |vocabulary|
        control = document.cdef_controls.build(source_vocabulary: vocabulary, title: "x", row_order: 0)
        expect(control).to be_valid, "#{vocabulary} should be a permitted vocabulary"
      end
    end

    # Recorded at import rather than inferred later. A typo must fail loudly
    # rather than become a silent fourth vocabulary.
    it "rejects anything else" do
      control = document.cdef_controls.build(source_vocabulary: "sechub", title: "x", row_order: 0)

      expect(control).not_to be_valid
      expect(control.errors[:source_vocabulary]).to be_present
    end

    it "tolerates nil for rows the backfill has not reached" do
      control = document.cdef_controls.build(source_vocabulary: nil, title: "x", row_order: 0)

      expect(control).to be_valid
    end
  end

  describe "#source_identifier" do
    it "prefers the dedicated column" do
      control = document.cdef_controls.create!(
        source_control_id: "IAM.3", stig_id: "SV-1r1_rule", title: "x", row_order: 0
      )

      expect(control.source_identifier).to eq("IAM.3")
    end

    # Rows read correctly between the schema migration and the deferred backfill
    # completing — otherwise the CDEF screen would blank out during that window.
    it "falls back to the legacy STIG columns" do
      control = document.cdef_controls.create!(
        source_control_id: nil, stig_id: "SV-1r1_rule", title: "x", row_order: 0
      )

      expect(control.source_identifier).to eq("SV-1r1_rule")
    end

    it "is what the unmapped-rule display uses" do
      control = document.cdef_controls.create!(
        source_control_id: nil, rule_id: "SV-2r1_rule", title: "x", row_order: 0
      )

      expect(control.provenance_id).to eq("SV-2r1_rule")
    end
  end
end
