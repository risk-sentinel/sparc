# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261103120000_ensure_ssp_statement_rows.rb")

# #1328 — an SSP whose controls hold only `<control>_smt` (created before
# v1.17.4, imported, or built from a baseline whose cached catalog is
# flattened) counted "0/N answered" and offered only Notes in Edit, because the
# editor answers rows that exist and none existed for the items.
#
# SspStatementRows adds the rows from the tree the counts read
# (ControlRequirementText), so every counted item can be answered. It runs at
# SSP creation, at import, and once over existing SSPs (EnsureSspStatementRows).
RSpec.describe SspStatementRows do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }

  # ac-1 as NIST divides it: a lead-in (a.) over two items, and b.
  let!(:catalog_control) do
    create(:catalog_control, control_family: family, control_id: "ac-1").tap do |cc|
      [ [ "ac-1_smt", nil, nil ],
        [ "ac-1_smt.a", "ac-1_smt", "a." ],
        [ "ac-1_smt.a.1", "ac-1_smt.a", "1." ],
        [ "ac-1_smt.a.2", "ac-1_smt.a", "2." ],
        [ "ac-1_smt.b", "ac-1_smt", "b." ] ].each_with_index do |(pid, parent, label), order|
        cc.catalog_control_parts.create!(part_id: pid, parent_part_id: parent, label: label,
                                         part_name: pid == "ac-1_smt" ? "statement" : "item",
                                         prose: "prose #{pid}", row_order: order, uuid: SecureRandom.uuid)
      end
    end
  end

  # The cached resolved catalog is FLATTENED, as every profile resolved before
  # #1100 is: one statement, no items.
  let(:flattened_catalog_json) do
    { "catalog" => { "uuid" => SecureRandom.uuid, "metadata" => { "title" => "Flat", "oscal-version" => "1.1.2" },
                     "groups" => [ { "id" => "ac", "title" => "Access Control",
                                     "controls" => [ { "id" => "ac-1", "title" => "Policy",
                                                       "parts" => [ { "id" => "ac-1_smt", "name" => "statement",
                                                                      "prose" => "flattened" } ] } ] } ] } }
  end

  # The baseline selects ac-1, which is what the response counts read.
  def profile_with(catalog:)
    create(:profile_document, control_catalog: catalog, lifecycle_status: "published",
                              published: Time.current.iso8601, resolved_catalog_json: flattened_catalog_json)
      .tap { |profile| create(:profile_control, profile_document: profile, control_id: "ac-1") }
  end

  def old_shape_ssp(profile)
    create(:ssp_document, profile_document: profile).tap do |ssp|
      ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy").ssp_control_statements
         .create!(statement_id: "ac-1_smt", row_order: 0, uuid: SecureRandom.uuid,
                  implementation_prose: "AUTHORED BY A HUMAN")
    end
  end

  def statement_ids(ssp) = ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.reload.pluck(:statement_id)

  def all_items = %w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.a.2 ac-1_smt.b]

  describe ".ensure!" do
    it "adds a row for every item of an SSP that holds only the whole-control row" do
      ssp = old_shape_ssp(profile_with(catalog: catalog))

      expect(described_class.ensure!(ssp)).to eq(4)
      expect(statement_ids(ssp)).to match_array(all_items)
    end

    # The shape the customer's SSP was in: a resolved baseline with no catalog
    # link. The 2026-09-08 re-backfill read only a LINKED catalog's parts, so it
    # added nothing here, and that is how this SSP kept the old shape.
    it "adds them when the baseline names no catalog, where the old backfill added nothing" do
      ssp = old_shape_ssp(profile_with(catalog: nil))
      expect(CatalogPartExtractorService.new(ssp).backfill_ssp_statements!).to eq(0)

      described_class.ensure!(ssp)

      expect(statement_ids(ssp)).to match_array(all_items)
    end

    it "gives every item the baseline counts a row the editor answers in" do
      ssp = old_shape_ssp(profile_with(catalog: catalog))
      before = SspResponseProgress.new(ssp)
      expect(before.parts_for("ac-1").map(&:part_id)).to eq(%w[ac-1_smt.a.1 ac-1_smt.a.2 ac-1_smt.b])
      expect(before.parts_for("ac-1").filter_map(&:statement_id)).to be_empty

      described_class.ensure!(ssp)

      after = SspResponseProgress.new(ssp.reload)
      expect(after.parts_for("ac-1").map(&:part_id)).to eq(%w[ac-1_smt.a.1 ac-1_smt.a.2 ac-1_smt.b])
      expect(after.parts_for("ac-1").map(&:statement_id)).to all(be_present)
    end

    it "parents each item on its catalog part and keeps the catalog's labels and order" do
      ssp = old_shape_ssp(profile_with(catalog: catalog))
      described_class.ensure!(ssp)

      rows = ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.order(:row_order)
                .pluck(:statement_id, :parent_statement_id, :label)
      expect(rows).to include([ "ac-1_smt.a", "ac-1_smt", "a." ], [ "ac-1_smt.a.1", "ac-1_smt.a", "1." ],
                              [ "ac-1_smt.b", "ac-1_smt", "b." ])
    end

    it "derives each new row's UUID the way SSP creation does" do
      ssp = old_shape_ssp(profile_with(catalog: catalog))
      described_class.ensure!(ssp)

      control = ssp.ssp_controls.find_by(control_id: "ac-1")
      row = control.ssp_control_statements.find_by(statement_id: "ac-1_smt.b")
      expect(row.uuid).to eq(OscalUuidService.derived(control.uuid, "ssp-statement", "ac-1_smt.b"))
    end

    it "never changes an existing row's answer" do
      ssp = old_shape_ssp(profile_with(catalog: catalog))
      described_class.ensure!(ssp)

      root = ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.find_by(statement_id: "ac-1_smt")
      expect(root.implementation_prose).to eq("AUTHORED BY A HUMAN")
    end

    it "adds nothing the second time, and treats an existing row's id without regard to case" do
      ssp = old_shape_ssp(profile_with(catalog: catalog))
      ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements
         .create!(statement_id: "AC-1_SMT.B", row_order: 9, uuid: SecureRandom.uuid)

      expect(described_class.ensure!(ssp)).to eq(3)
      expect(described_class.ensure!(ssp)).to eq(0)
      expect(statement_ids(ssp).map(&:downcase).tally.values).to all(eq(1))
    end

    it "adds rows for an imported SSP that has no baseline, from its control's catalog" do
      ssp = old_shape_ssp(nil)

      described_class.ensure!(ssp)

      expect(statement_ids(ssp)).to match_array(all_items)
    end

    # #955 — a control the catalog gives no statement (guidance only) has no
    # statement row, and the repair must not invent one.
    it "adds no row for a control whose catalog entry has no statement" do
      create(:catalog_control, control_family: family, control_id: "ac-9", guidance_data: {})
      ssp = old_shape_ssp(profile_with(catalog: catalog))
      ssp.ssp_controls.create!(control_id: "ac-9", title: "Guidance only")

      described_class.ensure!(ssp)

      expect(ssp.ssp_controls.find_by(control_id: "ac-9").ssp_control_statements).to be_empty
    end

    it "leaves a control the catalogs do not hold alone" do
      ssp = old_shape_ssp(profile_with(catalog: catalog))
      ssp.ssp_controls.create!(control_id: "zz-9", title: "Not in any catalog")

      expect { described_class.ensure!(ssp) }.not_to raise_error
      expect(ssp.ssp_controls.find_by(control_id: "zz-9").ssp_control_statements).to be_empty
    end
  end

  describe "SSP creation from a baseline whose cached catalog is flattened" do
    it "gives every control a row for every item" do
      ssp = SspFromProfileService.new(profile_with(catalog: catalog),
                                      authorization_boundary: create(:authorization_boundary)).create

      expect(statement_ids(ssp)).to match_array(all_items)
    end
  end

  describe "an imported SSP that answers only the whole control" do
    it "gets a row for every item, and the control-level status reaches each" do
      document = create(:ssp_document, profile_document: nil)
      SspJsonParserService.new(document, nil).parse_from_hash(
        "system-security-plan" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Imported", "oscal-version" => "1.1.2" },
          "import-profile" => { "href" => "#none" },
          "system-characteristics" => {
            "system-ids" => [ { "id" => "SYS-1" } ], "system-name" => "Imported", "description" => "d",
            "status" => { "state" => "operational" }, "security-impact-level" => {},
            "authorization-boundary" => { "description" => "b" },
            "system-information" => { "information-types" => [] }
          },
          "system-implementation" => {
            "components" => [ { "uuid" => SecureRandom.uuid, "type" => "this-system", "title" => "Imported",
                                "description" => "d", "status" => { "state" => "operational" } } ],
            "users" => []
          },
          "control-implementation" => {
            "description" => "c",
            "implemented-requirements" => [
              { "uuid" => SecureRandom.uuid, "control-id" => "ac-1",
                "props" => [ { "name" => "implementation-status", "value" => "implemented" } ] }
            ]
          }
        }
      )

      control = document.ssp_controls.find_by(control_id: "ac-1")
      expect(control.ssp_control_statements.pluck(:statement_id)).to match_array(all_items)
      leaves = control.ssp_control_statements.where(statement_id: %w[ac-1_smt.a.1 ac-1_smt.a.2 ac-1_smt.b])
      expect(leaves.pluck(:implementation_status)).to all(eq("implemented"))
    end
  end

  describe EnsureSspStatementRows do
    subject(:migration) { described_class.new }

    before { allow(migration).to receive(:say) }

    around do |example|
      DeferredDataMigration.executing!
      example.run
    ensure
      DeferredDataMigration.idle!
    end

    it "gives every existing SSP its item rows, once" do
      linked = old_shape_ssp(profile_with(catalog: catalog))
      unlinked = old_shape_ssp(profile_with(catalog: nil))

      migration.up

      expect(statement_ids(linked)).to match_array(all_items)
      expect(statement_ids(unlinked)).to match_array(all_items)
      expect { migration.up }.not_to change { SspControlStatement.count }
    end

    it "keeps going past a document that fails" do
      broken = old_shape_ssp(profile_with(catalog: catalog))
      fine = old_shape_ssp(profile_with(catalog: catalog))
      allow(SspStatementRows).to receive(:ensure!).and_call_original
      allow(SspStatementRows).to receive(:ensure!).with(broken).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { migration.up }.not_to raise_error
      expect(statement_ids(fine)).to match_array(all_items)
    end
  end
end
