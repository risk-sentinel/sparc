# frozen_string_literal: true

require "rails_helper"

# #1100 — an SSP must be answerable per STATEMENT, not per control.
#
# OSCAL models this explicitly: `implemented-requirement.statements` is an array
# whose members "identify which statements within a control are addressed", and
# each carries its own `by-components` where the implementation prose lives.
#
# SPARC generated ONE `<control-id>_smt` row per control — measured on the demo
# estate, 149 statements for 150 controls, zero with more than one. An author
# had a single box in which to answer a control NIST divides into nine parts,
# and the export said the whole control was satisfied by one undifferentiated
# response.
#
# The chain had four places to drop the tree, and did so at the first:
#
#   importer discarded ctrl["parts"]      -> catalog_control_parts empty
#   resolver emitted one flattened part   -> profile carried no structure
#   generator took the single statement id -> one row per control
#   export emitted what it was given      -> one statement per requirement
#
# This asserts the whole chain end to end, because fixing any one layer while
# another still flattens leaves the same symptom with a different cause.
RSpec.describe "SSP statements are generated per catalog statement part (#1100)" do
  let(:catalog)  { create(:control_catalog, name: "Test Catalog") }
  let(:family)   { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:control) do
    family.catalog_controls.create!(
      control_id: "ac-1", title: "Policy and Procedures",
      guidance_data: { "statement" => "a. Develop...\n  1. a policy that:\n    (a) Addresses purpose;" }
    )
  end

  # The tree as NIST ships it: a "statement" container whose children are "item".
  before do
    rows = [
      [ "ac-1_smt",       nil,            nil,  nil,  0 ],
      [ "ac-1_smt.a",     "ac-1_smt",     "a.", "Develop, document, and disseminate:", 1 ],
      [ "ac-1_smt.a.1",   "ac-1_smt.a",   "1.", "an access control policy that:",      2 ],
      [ "ac-1_smt.a.1.a", "ac-1_smt.a.1", "(a)", "Addresses purpose and scope;",       3 ],
      [ "ac-1_smt.b",     "ac-1_smt",     "b.", "Designate an official;",              4 ]
    ]
    rows.each do |part_id, parent, label, prose, order|
      control.catalog_control_parts.create!(
        part_id: part_id, part_name: part_id == "ac-1_smt" ? "statement" : "item",
        parent_part_id: parent, label: label, prose: prose, row_order: order,
        uuid: SecureRandom.uuid
      )
    end
  end

  let(:profile)  { create(:profile_document, control_catalog: catalog, lifecycle_status: "published") }
  let!(:pctrl)   { profile.profile_controls.create!(control_id: "ac-1", title: "Policy and Procedures") }
  let(:boundary) { create(:authorization_boundary) }

  # Resolve the profile through the REAL resolver rather than hand-writing a
  # resolved catalog. That is what makes this end to end: if the resolver
  # flattens the statement tree, the generator has nothing to walk and these
  # examples fail — which is the bug they exist to catch.
  before do
    profile.update!(resolved_catalog_json: JSON.parse(OscalResolvedProfileCatalogService.new(profile).export))
  end

  subject(:ssp) do
    SspFromProfileService.new(profile, name: "Generated SSP", authorization_boundary: boundary).create
  end

  it "creates one statement per catalog statement part, not one per control" do
    control_row = ssp.ssp_controls.find_by(control_id: "ac-1")
    ids = control_row.ssp_control_statements.pluck(:statement_id).sort

    expect(ids).to eq(%w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.a.1.a ac-1_smt.b]),
      "a control NIST divides into parts must be answerable per part"
  end

  it "mirrors the catalog's nesting so an author can see which part they answer" do
    stmts = ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.index_by(&:statement_id)

    # `parent_statement_id` holds the parent's CATALOG statement id, not a row
    # FK — the convention CatalogPartExtractorService set and that the CDEF
    # inheritance and leveraged-authorization services both rely on when they
    # copy statements between documents.
    expect(stmts["ac-1_smt"].parent_statement_id).to be_nil
    expect(stmts["ac-1_smt.a"].parent_statement_id).to eq("ac-1_smt")
    expect(stmts["ac-1_smt.a.1"].parent_statement_id).to eq("ac-1_smt.a")
    expect(stmts["ac-1_smt.a.1.a"].parent_statement_id).to eq("ac-1_smt.a.1")
    expect(stmts["ac-1_smt.b"].parent_statement_id).to eq("ac-1_smt")
  end

  it "carries the catalog's label so the row reads as (a) rather than an opaque id" do
    stmts = ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.index_by(&:statement_id)

    expect(stmts["ac-1_smt.a.1.a"].label).to eq("(a)")
  end

  it "leaves implementation prose EMPTY — the author's response is not the requirement" do
    prose = ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.pluck(:implementation_prose)

    expect(prose.compact).to be_empty,
      "a freshly generated SSP has no answers yet; copying the catalog text in " \
      "would look like an implementation nobody wrote"
  end

  it "exports one OSCAL statement per part, and still validates against the 1.2.2 schema" do
    json = JSON.parse(OscalSspExportService.new(ssp).export_unvalidated)
    ir = json.dig("system-security-plan", "control-implementation", "implemented-requirements")
             .find { |r| r["control-id"] == "ac-1" }

    ids = ir["statements"].map { |s| s["statement-id"] }
    expect(ids).to include("ac-1_smt.a", "ac-1_smt.a.1.a", "ac-1_smt.b")
    expect(ir["statements"].size).to be >= 5

    expect { OscalSspExportService.new(ssp).export }.not_to raise_error
  end
end
