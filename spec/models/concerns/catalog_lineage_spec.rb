# frozen_string_literal: true

require "rails_helper"

# #911 layer 2 — every document must be able to name the catalog it descends
# from, through the OSCAL import chain.
#
# OSCAL makes the import mandatory at every hop; SPARC made each one optional,
# so a SPARC-authored document could end up untraceable. The columns already
# existed and the parsers already read the hrefs — they were simply unpopulated
# for documents SPARC authored rather than imported.
RSpec.describe CatalogLineage, type: :model do
  # Each document type and the hop OSCAL requires of it. Listed explicitly so
  # adding a document type without declaring its lineage fails here.
  LINEAGE_CHAIN = {
    ProfileDocument => :control_catalog,
    SspDocument     => :profile_document,
    SapDocument     => :ssp_document,
    SarDocument     => :sap_document,
    PoamDocument    => :ssp_document,
    CdefDocument    => :profile_document
  }.freeze

  it "is declared by every document type in the OSCAL chain" do
    LINEAGE_CHAIN.each_key do |klass|
      expect(klass.ancestors).to include(described_class),
        "#{klass} sits in the OSCAL import chain but declares no lineage"
      expect(klass.lineage_defs).not_to be_empty, "#{klass} includes the concern but declares no hop"
    end
  end

  # Found by running the API contract suite against the prod image: 14 of its
  # update tests failed with 422 because they create a document and immediately
  # PATCH it. `create` is not gated but `update` was, so the API let an
  # integrator make a document and then refused every edit to it.
  #
  # The gate's own justification is that "controls cannot be traced to a
  # catalog". A document with no controls has nothing to trace, so there is
  # nothing to reconcile and nothing to refuse.
  describe "a document that references no controls" do
    subject(:document) { create(:ssp_document, profile_document: nil) }

    it "reports nothing" do
      expect(document.ssp_controls).to be_empty
      expect(document.reconciliation).to be_nil
      expect(document).to be_lineage_resolved
    end

    it "does not block an update" do
      expect(document.reconciliation_blocks_update?).to be(false)
    end

    # The prompt appears when it becomes meaningful, not before.
    it "starts reporting as soon as it claims a control" do
      create(:ssp_control, ssp_document: document, control_id: "ac-1")

      expect(document.reload.reconciliation_blocks_update?).to be(true)
      expect(document.reconciliation[:issues].first[:code]).to eq("missing_profile_source")
    end

    it "applies to every lineage-bearing type" do
      LINEAGE_CHAIN.each_key do |klass|
        expect(klass.lineage_control_association).to be_present,
          "#{klass} must declare which association holds its control references"
      end
    end
  end

  describe "an unresolved document" do
    subject(:document) do
      create(:ssp_document, profile_document: nil, import_profile_href: nil).tap do |ssp|
        create(:ssp_control, ssp_document: ssp, control_id: "ac-1")
      end
    end

    it "is not resolved" do
      expect(document).not_to be_lineage_resolved
    end

    it "reports the missing source with a remedy the caller can act on" do
      issue = document.reconciliation[:issues].first

      expect(issue[:code]).to eq("missing_profile_source")
      expect(issue[:message]).to include("cannot be traced to a catalog")
      expect(issue[:remedy]).to include("profile_document_id")
      expect(issue[:options]).to eq("/api/v1/profile_documents")
    end

    it "blocks an update" do
      expect(document.reconciliation_blocks_update?).to be(true)
      expect(document.reconciliation[:blocking]).to eq([ "update" ])
    end
  end

  # A populated href that resolves to nothing is a DIFFERENT failure from no
  # href at all: the import named something SPARC cannot find, which is broken
  # at the root rather than merely unset. Reporting both as "not set yet" hides
  # a broken reference behind a routine one.
  describe "a document whose import names something unloadable" do
    subject(:document) do
      create(:ssp_document, profile_document: nil,
             import_profile_href: "#/profiles/fedramp-high-that-was-never-loaded").tap do |doc|
        create(:ssp_control, ssp_document: doc, control_id: "ac-1")
      end
    end

    it "distinguishes it from a document with no baseline at all" do
      issue = document.reconciliation[:issues].first

      expect(issue[:code]).to eq("unresolved_profile_source")
      expect(issue[:message]).to include("fedramp-high-that-was-never-loaded")
      expect(issue[:message]).to include("does not resolve")
    end

    it "still blocks an update" do
      expect(document.reconciliation_blocks_update?).to be(true)
    end
  end

  describe "a resolved document" do
    subject(:document) do
      create(:ssp_document, profile_document: create(:profile_document, control_catalog: create(:control_catalog)))
    end

    it "is resolved and reports nothing" do
      expect(document).to be_lineage_resolved
      expect(document.reconciliation).to be_nil
    end

    it "does not block an update" do
      expect(document.reconciliation_blocks_update?).to be(false)
    end
  end

  # `import-ap` is the ONLY import on assessment-results and it is required —
  # verified against the 1.1.2 and 1.2.1 schemas, neither of which has an
  # `import-ssp` property. The SSP is reached transitively via the AP, so
  # `sar_documents.ssp_document_id` is a convenience FK, not a lineage hop.
  describe "a SAR with its SSP but no assessment plan" do
    subject(:sar) do
      create(:sar_document, sap_document: nil, ssp_document: create(:ssp_document)).tap do |doc|
        create(:sar_control, sar_document: doc, control_id: "ac-1")
      end
    end

    it "is still unresolved — OSCAL requires import-ap" do
      expect(sar).not_to be_lineage_resolved
      expect(sar.reconciliation_blocks_update?).to be(true)
    end

    it "says it is traceable but incomplete, not untraceable" do
      issue = sar.reconciliation[:issues].first

      expect(issue[:code]).to eq("incomplete_assessment_plan_source")
      expect(issue[:message]).to include("traceable to a catalog")
      expect(issue[:message]).to include("will not validate")
      expect(issue[:message]).not_to include("cannot be traced")
    end

    it "reports a SAR with neither differently" do
      bare = create(:sar_document, sap_document: nil, ssp_document: nil)
      create(:sar_control, sar_document: bare, control_id: "ac-1")

      expect(bare.reconciliation[:issues].first[:code]).to eq("missing_assessment_plan_source")
      expect(bare.reconciliation[:issues].first[:message]).to include("cannot be traced")
    end

    it "resolves once the assessment plan is linked" do
      sar.update!(sap_document: create(:sap_document))

      expect(sar.reload).to be_lineage_resolved
    end
  end

  # Issue codes are matched by integrators, so they must be stable slugs — not
  # prose. A label like "assessment plan" or "SSP" would otherwise leak a space
  # or stray capitals into the code.
  it "emits machine-matchable issue codes" do
    LINEAGE_CHAIN.each_key do |klass|
      klass.lineage_defs.each do |definition|
        expect(definition[:key].to_s).to match(/\A[a-z][a-z0-9_]*\z/),
          "#{klass} lineage key #{definition[:key].inspect} is not a usable code slug"
      end
    end
  end

  # OSCAL lets a POA&M carry either `import-ssp` or a system identifier, so the
  # boundary satisfies the hop on its own.
  describe "either/or hops" do
    it "accepts a POA&M linked only to a boundary" do
      poam = create(:poam_document, ssp_document: nil,
                    authorization_boundary: create(:authorization_boundary))

      expect(poam).to be_lineage_resolved
    end

    it "accepts a POA&M linked only to an SSP" do
      poam = create(:poam_document, ssp_document: create(:ssp_document),
                    authorization_boundary: nil)

      expect(poam).to be_lineage_resolved
    end

    it "reports a POA&M with neither" do
      poam = create(:poam_document, ssp_document: nil, authorization_boundary: nil)
      create(:poam_item, poam_document: poam)

      expect(poam).not_to be_lineage_resolved
    end
  end

  # Layer 1 already reports unmapped STIG rules. They belong in the SAME object
  # as lineage, not a field of their own.
  describe "issues beyond the import chain" do
    subject(:cdef) { create(:cdef_document, profile_document: nil) }

    before do
      cdef.cdef_controls.create!(stig_id: "SV-999999r000001_rule",
                                 rule_id: "SV-999999r000001_rule",
                                 title: "Unmapped", row_order: 0)
    end

    it "reports lineage and unmapped rules together" do
      codes = cdef.reload.reconciliation[:issues].map { _1[:code] }

      expect(codes).to include("missing_profile_source", "unmapped_stig_rules")
    end

    # An unmapped rule is a finding to act on, not a reason to refuse a write.
    # Only the missing import blocks here.
    it "blocks on the lineage gap, not on the unmapped rule" do
      resolved = create(:cdef_document,
                        profile_document: create(:profile_document, control_catalog: create(:control_catalog)))
      resolved.cdef_controls.create!(stig_id: "SV-999999r000001_rule",
                                     rule_id: "SV-999999r000001_rule",
                                     title: "Unmapped", row_order: 0)

      expect(resolved.reload.reconciliation_blocks_update?).to be(false)
      expect(resolved.reconciliation[:blocking]).to eq([])
      expect(resolved.reconciliation[:issues].map { _1[:code] }).to eq([ "unmapped_stig_rules" ])
    end
  end

  # The 422 body and the advisory payload are the same object. An integrator
  # writes one handler; `blocking` is the only thing that differs.
  describe "the reported shape" do
    it "carries code, message and remedy on every issue" do
      document = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: document, control_id: "ac-1")

      document.reconciliation[:issues].each do |issue|
        expect(issue[:code]).to be_present
        expect(issue[:message]).to be_present
        expect(issue[:remedy]).to be_present
      end
    end

    it "always reports status alongside blocking" do
      document = create(:ssp_document, profile_document: nil)
      create(:ssp_control, ssp_document: document, control_id: "ac-1")

      expect(document.reconciliation).to include(status: "unresolved")
      expect(document.reconciliation.keys).to include(:status, :blocking, :issues)
    end
  end
end
