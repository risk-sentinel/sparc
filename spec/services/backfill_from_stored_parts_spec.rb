# frozen_string_literal: true

require "rails_helper"

# #1100 — the fifth layer.
#
# The chain was importer -> resolver -> generator -> export, and all four were
# fixed. The BACKFILL for documents that already exist reads a fifth source: the
# profile's `resolved_catalog_json`, which is CACHED. Every profile resolved
# before #1100 holds the flattened single statement, and nothing re-resolves an
# existing profile — so the backfill saw one part, found it already present, and
# added nothing. Every existing SSP kept exactly one statement per control and
# the per-statement editor had nothing to edit.
#
# Measured on the seeded estate before the fix: AC-1 had 1 statement while
# `catalog_control_parts` held 10. After: 10, and 575 across the document.
RSpec.describe "SSP statement backfill when the profile's resolved catalog is stale" do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }

  let!(:catalog_control) do
    create(:catalog_control, control_family: family, control_id: "ac-1").tap do |cc|
      [ [ "ac-1_smt", nil, nil, 0 ],
        [ "ac-1_smt.a", "ac-1_smt", "a.", 1 ],
        [ "ac-1_smt.a.1", "ac-1_smt.a", "1.", 2 ],
        [ "ac-1_smt.b", "ac-1_smt", "b.", 3 ] ].each do |pid, parent, label, order|
        cc.catalog_control_parts.create!(part_id: pid, parent_part_id: parent, label: label,
                                         part_name: "statement", prose: "prose #{pid}",
                                         row_order: order, uuid: SecureRandom.uuid)
      end
    end
  end

  # The stale shape: exactly what a pre-#1100 resolver emitted — ONE flattened
  # statement, no tree.
  let(:stale_resolved_catalog) do
    { "catalog" => { "controls" => [ { "id" => "ac-1", "title" => "Policy",
                                       "parts" => [ { "id" => "ac-1_smt", "name" => "statement",
                                                      "prose" => "flattened" } ] } ] } }
  end

  let(:profile) do
    create(:profile_document, control_catalog: catalog, resolved_catalog_json: stale_resolved_catalog)
  end

  let(:ssp) { create(:ssp_document, profile_document: profile) }

  before do
    ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy").tap do |c|
      c.ssp_control_statements.create!(statement_id: "ac-1_smt", row_order: 0, uuid: SecureRandom.uuid)
    end
  end

  it "adds the sub-part statements the stale catalog cannot supply" do
    control = ssp.ssp_controls.find_by(control_id: "ac-1")
    expect(control.ssp_control_statements.count).to eq(1)

    added = CatalogPartExtractorService.new(ssp).backfill_ssp_statements!

    expect(added).to eq(3)
    expect(control.ssp_control_statements.reload.pluck(:statement_id))
      .to match_array(%w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.b])
  end

  it "keeps parent_statement_id as the CATALOG id, which the inheritance services join on" do
    CatalogPartExtractorService.new(ssp).backfill_ssp_statements!
    control = ssp.ssp_controls.find_by(control_id: "ac-1")

    parents = control.ssp_control_statements.reload.to_h { |s| [ s.statement_id, s.parent_statement_id ] }
    expect(parents["ac-1_smt.a"]).to eq("ac-1_smt")
    expect(parents["ac-1_smt.a.1"]).to eq("ac-1_smt.a")
    expect(parents["ac-1_smt"]).to be_nil
  end

  it "leaves an existing statement's authored prose alone" do
    control = ssp.ssp_controls.find_by(control_id: "ac-1")
    control.ssp_control_statements.first.update!(implementation_prose: "written by a human")

    CatalogPartExtractorService.new(ssp).backfill_ssp_statements!

    expect(control.ssp_control_statements.find_by(statement_id: "ac-1_smt").implementation_prose)
      .to eq("written by a human")
  end

  it "is idempotent — a second run adds nothing" do
    CatalogPartExtractorService.new(ssp).backfill_ssp_statements!
    expect(CatalogPartExtractorService.new(ssp).backfill_ssp_statements!).to eq(0)
  end
end
