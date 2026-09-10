# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260908120000_rebackfill_ssp_statement_sub_parts.rb")

# #1100 — the SIXTH layer: the backfill that was supposed to fix existing
# documents ran BEFORE the extractor was fixed, completed, and can never run
# again.
#
#   BackfillSspStatementSubParts   v1.0.0   completed   2026-09-05 15:25:37
#   4bc6e839 fixed the extractor                        2026-09-07 09:42
#
# `DeferredDataMigrationRunner#run_all_pending` selects only `pending`/`failed`,
# and `register_pending_run!` never updates an existing row — so bumping
# `data_migration_version` on the original class would have been INERT. This
# migration exists under a NEW class name so it gets its own run row.
#
# These examples drive the migration body through `defer_data_migration`, with
# the executing flag set the way the runner sets it — so a body that only
# REGISTERS and never runs fails here rather than on a customer's database.
RSpec.describe RebackfillSspStatementSubParts do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

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

  # The profile cache is STALE — one flattened statement, no tree. This is the
  # condition every pre-#1100 profile is in, and the reason the original run
  # added nothing.
  let(:profile) do
    create(:profile_document,
           control_catalog: catalog,
           resolved_catalog_json: {
             "catalog" => { "controls" => [ { "id" => "ac-1", "title" => "Policy",
                                              "parts" => [ { "id" => "ac-1_smt",
                                                             "name" => "statement",
                                                             "prose" => "flattened" } ] } ] }
           })
  end

  let(:ssp)     { create(:ssp_document, profile_document: profile) }
  let(:control) { ssp.ssp_controls.find_by(control_id: "ac-1") }

  # Exactly what the completed-but-broken run left behind: one statement per
  # control, carrying prose somebody wrote against it.
  before do
    ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy").tap do |c|
      c.ssp_control_statements.create!(statement_id: "ac-1_smt", row_order: 0,
                                       uuid: SecureRandom.uuid,
                                       implementation_prose: "AUTHORED BY A HUMAN")
    end
  end

  it "adds the sub-parts the completed run never did" do
    expect(control.ssp_control_statements.count).to eq(1)

    migration.up

    expect(control.ssp_control_statements.reload.pluck(:statement_id))
      .to match_array(%w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.b])
  end

  # The whole reason this is additive rather than a regenerate: the `_smt` row an
  # existing SSP carries may hold the only implementation narrative the document
  # has. Replacing it to tidy the shape would destroy what the feature exists to
  # hold.
  it "never overwrites prose already authored against an existing statement" do
    migration.up

    root = control.ssp_control_statements.reload.find_by(statement_id: "ac-1_smt")
    expect(root.implementation_prose).to eq("AUTHORED BY A HUMAN")
  end

  it "parents sub-parts on the CATALOG statement id the inheritance services join on" do
    migration.up

    parents = control.ssp_control_statements.reload
                     .to_h { |s| [ s.statement_id, s.parent_statement_id ] }
    expect(parents["ac-1_smt.a"]).to eq("ac-1_smt")
    expect(parents["ac-1_smt.a.1"]).to eq("ac-1_smt.a")
  end

  # Resume-from-partial: the estate already contains one document that was
  # hand-run during 4bc6e839's verification, so this migration MUST be a no-op
  # over documents that already have their sub-parts.
  it "adds nothing on a second run" do
    migration.up
    before_ids = control.ssp_control_statements.reload.pluck(:statement_id).sort

    expect { migration.up }
      .not_to change { control.ssp_control_statements.reload.pluck(:statement_id).sort }

    expect(before_ids.size).to eq(4)
  end

  # A document whose catalog cannot be resolved must not strand the run — the
  # migration rescues per document precisely so one bad SSP cannot stop the rest.
  it "keeps going when one document cannot resolve a catalog" do
    create(:ssp_document, profile_document: nil).ssp_controls
      .create!(control_id: "au-1", title: "Orphan")

    expect { migration.up }.not_to raise_error
    expect(control.ssp_control_statements.reload.count).to eq(4)
  end
end
