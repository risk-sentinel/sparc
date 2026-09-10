# frozen_string_literal: true

require "rails_helper"

# #1088 — the "Baseline not set" prompt on every AWS Labs component definition.
#
# `lineage_via :profile_document` (#911) demands exactly ONE profile before a
# CDEF may be edited, and blocks with "No imported profile; controls cannot be
# traced to a catalog" until it is chosen. Owner review: "I'm not sure why the
# association to a profile is needed. We have an AWS to NIST converter that
# relates the AWS Controls to NIST 800-53 R4 and R5."
#
# Checked against the format rather than argued: `control-implementations` is an
# ARRAY on `defined-component` in the OSCAL v1.2.2 schema, each entry REQUIRING
# its own `source`, documented as "a reference to an OSCAL catalog or profile".
# One CDEF implementing controls from several catalogs and several profiles is
# what the format models, and a single foreign key cannot express it.
#
# So #911's guarantee is kept — controls must be traceable to a catalog — and
# the mechanism becomes the one OSCAL uses.
RSpec.describe "CDEF lineage from control-implementation sources" do
  let(:document) { create(:cdef_document, profile_document: nil) }

  def control(source:, control_id: "ac-2")
    document.cdef_controls.create!(control_id: control_id, title: control_id,
                                   implementation_source: source)
  end

  it "is resolved when every control names its own source" do
    control(source: "https://example.test/catalogs/nist-800-53-rev5")

    expect(document.reload.lineage_issues).to be_empty
    expect(document).to be_lineage_resolved
    expect(document.reconciliation_blocks_update?).to be(false)
  end

  # The whole point of item 4: more than one catalog, at once.
  it "is resolved when its controls span several catalogs" do
    control(source: "https://example.test/catalogs/nist-800-53-rev5", control_id: "ac-2")
    control(source: "https://example.test/catalogs/nist-800-53-rev4", control_id: "ca-7")

    expect(document.reload).to be_lineage_resolved
    expect(document.declared_control_sources.size).to eq(2)
  end

  # The guarantee is not weakened: a control with no source is still untraceable,
  # and the document must still say so.
  it "still blocks when a control declares no source" do
    control(source: "https://example.test/catalogs/nist-800-53-rev5", control_id: "ac-2")
    control(source: nil, control_id: "ca-7")

    document.reload
    expect(document.lineage_issues).not_to be_empty
    expect(document.reconciliation_blocks_update?).to be(true)
  end

  it "still blocks a document with controls and no sources at all" do
    control(source: nil)

    expect(document.reload.reconciliation_blocks_update?).to be(true)
  end

  # A document claiming no controls was never prompted (#911 commit 2) and must
  # not start being prompted now.
  it "leaves a document with no controls alone" do
    expect(document.reload.lineage_issues).to be_empty
  end

  it "still accepts a named profile, for documents authored against one" do
    profile = create(:profile_document)
    document.update!(profile_document: profile)
    control(source: nil)

    expect(document.reload).to be_lineage_resolved
  end
end
