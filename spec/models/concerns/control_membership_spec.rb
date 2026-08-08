# frozen_string_literal: true

require "rails_helper"

# #911 layer 3 — is each control actually IN this document's baseline?
#
# Stronger than "this identifier exists somewhere": a control can be a real NIST
# control and still be out of scope for the system claiming it. Reported, never
# blocking — a system legitimately implements more than its baseline.
RSpec.describe ControlMembership, type: :model do
  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog) }
  let(:profile) { create(:profile_document, control_catalog: catalog) }

  def catalog_control(id)
    create(:catalog_control, control_family: family, control_id: id)
  end

  # Every type that owns controls drawn from a baseline.
  it "is declared by each document type that selects from a baseline" do
    [ ProfileDocument, SspDocument, SapDocument, SarDocument, CdefDocument ].each do |klass|
      expect(klass.ancestors).to include(described_class), "#{klass} owns controls but declares no membership"
      expect(klass.membership_def).to be_present
    end
  end

  describe "an SSP against its profile's selection" do
    let(:ssp) { create(:ssp_document, profile_document: profile) }

    before do
      catalog_control("ac-1")
      catalog_control("ac-2")
      create(:profile_control, profile_document: profile, control_id: "ac-1")
    end

    it "reports nothing when every control is in the baseline" do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-1")

      expect(ssp.out_of_baseline_control_ids).to be_empty
      expect(ssp.membership_issues).to be_empty
    end

    it "reports a control the profile does not select" do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-1")
      create(:ssp_control, ssp_document: ssp, control_id: "ac-2")

      expect(ssp.out_of_baseline_control_ids).to contain_exactly("ac-2")
      expect(ssp.membership_issues.first[:code]).to eq("controls_outside_baseline")
      expect(ssp.membership_issues.first[:authority]).to eq("authoritative")
    end

    # The comparison is canonical on BOTH sides. A baseline holding `AC-02` and a
    # document holding `ac-2` name the same control; comparing literally would
    # flag every row and destroy trust in the check immediately.
    it "does not flag a control the baseline spells differently" do
      create(:profile_control, profile_document: profile, control_id: "AC-02")
      create(:ssp_control, ssp_document: ssp, control_id: "ac-2")

      expect(ssp.out_of_baseline_control_ids).not_to include("ac-2")
    end

    # The measured case from the issue: relating the demo SSP to the only loaded
    # profile flags 53 of 55, because that profile is not that system's baseline.
    # Refusing on that would be refusing on SPARC's own bad guess.
    it "never blocks, however many controls fall outside" do
      10.times { |i| create(:ssp_control, ssp_document: ssp, control_id: "sc-#{i + 1}") }

      expect(ssp.out_of_baseline_control_ids.size).to eq(10)
      expect(ssp.reconciliation[:blocking]).to eq([]),
        "membership is a finding to act on, not an error to refuse on"
    end

    it "carries a remedy that treats the finding as a question, not a verdict" do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-2")

      expect(ssp.membership_issues.first[:remedy]).to include("Confirm these are intended")
    end
  end

  # No baseline means no in-scope answer. Saying so is the point: reporting a
  # weaker check as authoritative is how a document looks verified when nothing
  # verified it.
  describe "when lineage is unresolved" do
    let(:ssp) { create(:ssp_document, profile_document: nil) }

    before { catalog_control("ac-1") }

    it "degrades to existence-in-any-catalog, and labels it" do
      create(:ssp_control, ssp_document: ssp, control_id: "zz-99")

      issue = ssp.membership_issues.first
      expect(ssp.membership_authority).to eq(ControlMembership::DEGRADED)
      expect(issue[:code]).to eq("controls_not_in_any_catalog")
      expect(issue[:authority]).to eq("degraded")
      expect(issue[:message]).to include("only check that the identifiers exist")
    end

    it "does not flag a control that exists in some loaded catalog" do
      create(:ssp_control, ssp_document: ssp, control_id: "AC-01")

      expect(ssp.out_of_baseline_control_ids).to be_empty
    end

    it "points at the baseline as the way to get a real answer" do
      create(:ssp_control, ssp_document: ssp, control_id: "zz-99")

      expect(ssp.membership_issues.first[:remedy]).to include("Set this document's baseline")
    end
  end

  # With nothing loaded there is no comparison to make. Flagging everything
  # would be worse than saying nothing.
  describe "when no catalog is loaded at all" do
    it "reports nothing rather than flagging every control" do
      ssp = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: ssp, control_id: "ac-1")

      expect(CatalogControl.count).to eq(0)
      expect(ssp.membership_authority).to eq(ControlMembership::UNAVAILABLE)
      expect(ssp.out_of_baseline_control_ids).to be_empty
    end
  end

  # Lineage, unmapped rules and membership reach the reader as one account.
  describe "reported alongside lineage" do
    it "appears in the same reconciliation object" do
      ssp = create(:ssp_document, profile_document: profile)
      catalog_control("ac-1")
      create(:profile_control, profile_document: profile, control_id: "ac-1")
      create(:ssp_control, ssp_document: ssp, control_id: "zz-99")

      expect(ssp.reconciliation[:issues].map { _1[:code] }).to include("controls_outside_baseline")
    end

    it "does not suppress a CDEF's unmapped-rule issue" do
      cdef = create(:cdef_document, profile_document: profile)
      cdef.cdef_controls.create!(stig_id: "SV-1r1_rule", rule_id: "SV-1r1_rule",
                                 title: "Unmapped", row_order: 0)

      expect(cdef.reload.reconciliation[:issues].map { _1[:code] }).to include("unmapped_stig_rules")
    end
  end
end
