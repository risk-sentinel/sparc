# frozen_string_literal: true

require "rails_helper"

# #911 — a STIG rule that resolves to no NIST control gets NO control identifier,
# and the gap is reported to a human with a remedy.
#
# A STIG rule reaches NIST through CCI (rule → CCI → 800-53). Where that
# resolution fails there is no control to name, so the parsers used to write the
# XCCDF rule id into `control_id` instead. That made `control_id` polymorphic —
# sometimes a catalog control, sometimes a scanner rule — and the two were
# indistinguishable at every consumer, including the OSCAL export, which
# published `sv-257777r925318_rule` into a `control-id` field.
#
# The rule id is not lost: `rule_id`, `group_id` and `stig_id` carry it, and they
# are the columns lookups already use.
RSpec.describe "unmapped STIG rules", type: :model do
  let(:fixture_path) do
    Rails.root.join("spec/fixtures/files/components/test-stig-xccdf-unmapped.xml").to_s
  end
  let(:document) { create(:cdef_document, file_type: "xccdf", status: "processing") }

  before { CdefXccdfParserService.new(document, fixture_path).parse and document.reload }

  let(:mapped)   { document.cdef_controls.find_by(stig_id: "SV-257777r925318_rule") }
  let(:unmapped) { document.cdef_controls.find_by(stig_id: "SV-999999r000001_rule") }

  describe "the parser" do
    it "still resolves the rule the CCI mapping covers" do
      expect(mapped.control_id).to be_present
      expect(mapped.control_id).not_to start_with("sv-")
    end

    it "leaves control_id null for the rule it cannot resolve" do
      expect(unmapped.control_id).to be_blank
    end

    it "never stores a rule id as a control identifier" do
      # The regression in one assertion: no row may name itself with an SV-ID.
      expect(document.cdef_controls.pluck(:control_id).compact)
        .to all(satisfy { |id| !id.match?(/\Asv-\d+/i) })
    end

    it "keeps the XCCDF provenance on the unmapped rule" do
      expect(unmapped.rule_id).to eq("SV-999999r000001_rule")
      expect(unmapped.stig_id).to eq("SV-999999r000001_rule")
      expect(unmapped.group_id).to eq("V-999999")
    end

    it "keeps the rule's own content so nothing is silently dropped" do
      expect(unmapped.title).to eq("A rule the CCI mapping does not cover.")
      expect(unmapped.severity).to eq("low")
      expect(unmapped.cdef_control_fields.find_by(field_name: "fix_text").field_value)
        .to eq("Nothing to do.")
    end
  end

  describe "surfacing the gap" do
    it "identifies the unmapped rule" do
      expect(unmapped).to be_unmapped_stig_rule
      expect(mapped).not_to be_unmapped_stig_rule
    end

    it "offers the rule's own identifier for display" do
      expect(unmapped.provenance_id).to eq("SV-999999r000001_rule")
    end

    it "scopes to exactly the unmapped rules" do
      expect(document.cdef_controls.unmapped_stig_rules).to contain_exactly(unmapped)
    end

    it "counts them on the document" do
      expect(document.unmapped_stig_rule_count).to eq(1)
      expect(document).to be_unmapped_stig_rules
    end

    it "reports none when every rule resolves" do
      clean = create(:cdef_document, file_type: "xccdf", status: "processing")
      CdefXccdfParserService.new(
        clean, Rails.root.join("spec/fixtures/files/components/test-stig-xccdf.xml").to_s
      ).parse

      expect(clean.reload.unmapped_stig_rule_count).to eq(0)
      expect(clean).not_to be_unmapped_stig_rules
    end
  end

  describe "OSCAL export" do
    subject(:exported) do
      JSON.parse(OscalComponentDefinitionExportService.new(document).export_unvalidated)
    end

    let(:requirements) do
      exported.dig("component-definition", "components", 0, "control-implementations", 0,
                   "implemented-requirements")
    end

    it "omits the unmapped rule rather than inventing a control for it" do
      expect(requirements.length).to eq(1)
      expect(requirements.first["control-id"]).to eq(mapped.control_id)
    end

    it "never emits a placeholder control-id" do
      # The old blank-control_id fallback produced "unknown-<row id>" — a
      # well-formed token no validator would reject, asserting an implemented
      # requirement against a control that exists in no catalog.
      expect(requirements.map { _1["control-id"] }).to all(satisfy { |id| !id.start_with?("unknown-") })
    end

    it "refuses with a remedy when no rule maps to a control" do
      empty = create(:cdef_document, file_type: "xccdf", status: "processing")
      empty.cdef_controls.create!(
        stig_id: "SV-111111r000001_rule", rule_id: "SV-111111r000001_rule",
        title: "Unmapped", row_order: 0
      )

      expect { OscalComponentDefinitionExportService.new(empty.reload).export_unvalidated }
        .to raise_error(OscalValidationError, /stig_to_nist converter/)
    end
  end
end
