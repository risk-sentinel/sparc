# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261022120000_fix_rev5_develop_catalog_parts.rb")

# #1228 — existing installs take NIST's develop fixes to SA-15(13), SA-24 and
# SI-02(07) through a compare-and-swap repair. Driven through
# `defer_data_migration` with the executing flag set the way the runner sets
# it, so a body that only registers fails here.
#
# The catalogs are cut down to the families holding the three controls and
# imported through CatalogImportService, so the rows under repair are exactly
# the rows an import writes.
RSpec.describe FixRev5DevelopCatalogParts do
  subject(:migration) { described_class.new }

  let(:said) { [] }

  before { allow(migration).to receive(:say) { |message, *| said << message } }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  # NIST's catalog, only SA-15, SA-24 and SI-2 (enhancements included).
  def cut(full)
    data = full.deep_dup
    data["catalog"]["groups"] = data["catalog"]["groups"].filter_map do |group|
      next unless %w[sa si].include?(group["id"])

      group.merge("controls" => group["controls"].select { |c| %w[sa-15 sa-24 si-2].include?(c["id"]) })
    end
    data
  end

  def import(data, name: "cut.json")
    CatalogImportService.call(StringIO.new(JSON.generate(data)), name)[:catalog]
  end

  let(:released) { cut(JSON.parse(Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev5_catalog.json").read)) }
  let(:develop)  { cut(NistCatalogSource.catalog) }

  def control(catalog, id) = catalog.catalog_controls.find_by!(control_id: id)

  def state(catalog)
    described_class::CONTROL_IDS.to_h do |id|
      c = control(catalog, id)
      parts = c.catalog_control_parts.order(:row_order).map do |p|
        p.attributes.slice("part_id", "part_name", "label", "parent_part_id", "prose", "props_data", "row_order")
      end
      [ id, { "guidance_data" => c.guidance_data, "parts" => parts } ]
    end
  end

  # What a fresh import of NIST's corrected file stores, captured in a
  # savepoint and rolled back so it cannot leak into the catalog under repair.
  def develop_state
    snap = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      snap = state(import(develop))
      raise ActiveRecord::Rollback
    end
    snap
  end

  it "registers rather than runs when the runner is not executing it" do
    DeferredDataMigration.idle!
    expect { migration.up }.to change { DataMigrationRun.where(name: described_class.name).count }.by(1)
  end

  context "on a catalog imported from NIST's v5.2.0 release" do
    let!(:target) { develop_state }
    let!(:catalog) { import(released) }

    it "starts with NIST's errors in place" do
      expect(control(catalog, "sa-15.13").guidance_data["statement"]).to eq(described_class::OLD_SA_15_13_STATEMENT)
      expect(control(catalog, "sa-24").catalog_control_parts.where(part_id: "sa-24_obj.b-6")).to be_empty
    end

    it "leaves the three controls exactly as an import of NIST's fixed file would" do
      migration.up

      expect(state(catalog)).to eq(target)
    end

    it "gives the inserted parts the identity an import gives them" do
      migration.up
      sa24 = control(catalog, "sa-24")
      part = sa24.catalog_control_parts.find_by!(part_id: "sa-24_obj.b-6")

      expect(part.uuid).to eq(OscalUuidService.derived(sa24.uuid, "catalog-part:assessment-objective", "sa-24_obj.b-6"))
    end

    it "stamps the catalog with the commit, which the pre-release flag reads" do
      migration.up

      stamp = catalog.reload.metadata_extra["nist_develop_patch"]
      expect(stamp).to include("source_commit" => NistCatalogSource.source_commit)
      expect(catalog.nist_pre_release?).to be(true)
    end

    it "keeps a person's edit, skips the fix for that field or part only, and names it" do
      sa24 = control(catalog, "sa-24")
      sa24.update!(guidance_data: sa24.guidance_data.merge("assessment_objective" => "Invented objective text."))
      smt = control(catalog, "sa-15.13").catalog_control_parts.find_by!(part_id: "sa-15.13_smt")
      smt.update!(prose: "An invented, locally edited statement.")

      migration.up

      expect(control(catalog, "sa-24").guidance_data["assessment_objective"]).to eq("Invented objective text.")
      expect(smt.reload.prose).to eq("An invented, locally edited statement.")
      # Everything else is still fixed.
      expect(control(catalog, "sa-15.13").guidance_data).to eq(target.dig("sa-15.13", "guidance_data"))
      expect(control(catalog, "sa-24").catalog_control_parts.where(part_id: "sa-24_obj.b-10")).to exist
      expect(said).to include(
        a_string_including("catalog ##{catalog.id}", "sa-24 guidance assessment_objective was edited — kept"),
        a_string_including("catalog ##{catalog.id}", "sa-15.13 part sa-15.13_smt was edited — kept")
      )
    end

    it "finishes a run stopped part-way, and a further run changes nothing" do
      original = migration.method(:fix_control)
      calls = 0
      allow(migration).to receive(:fix_control) do |*args|
        calls += 1
        raise "stopped part-way" if calls == 2 # after SA-15(13) committed

        original.call(*args)
      end
      expect { migration.up }.to raise_error(RuntimeError, "stopped part-way")
      expect(control(catalog, "sa-15.13").guidance_data).to eq(target.dig("sa-15.13", "guidance_data"))
      expect(control(catalog, "sa-24").catalog_control_parts.where(part_id: "sa-24_obj.b-6")).to be_empty

      rerun = described_class.new
      allow(rerun).to receive(:say)
      rerun.up
      expect(state(catalog)).to eq(target)

      expect { rerun.up }.not_to(change { state(catalog) })
    end

    it "writes no SSP, SAP or SAR row, and names the SSPs still carrying the old SA-15(13) text" do
      stale = create(:ssp_document, name: "Invented Example SSP")
      ssp_control = create(:ssp_control, ssp_document: stale, control_id: "sa-15.13")
      create(:ssp_control_field, ssp_control: ssp_control, field_name: "stated_requirement",
                                 field_value: described_class::OLD_SA_15_13_STATEMENT, editable: false)
      # SA-15(12) legitimately carries this text; it must not be counted.
      other = create(:ssp_document, name: "Invented Twelve SSP")
      create(:ssp_control_field, ssp_control: create(:ssp_control, ssp_document: other, control_id: "sa-15.12"),
                                 field_name: "stated_requirement", field_value: described_class::OLD_SA_15_13_STATEMENT)
      create(:sap_document)
      create(:sar_document)

      tables = ActiveRecord::Base.connection.tables.grep(/\A(ssp|sap|sar)_/)
      fingerprint = lambda do
        tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_rows("SELECT * FROM #{t} ORDER BY 1") ] }
      end
      before = fingerprint.call

      migration.up

      expect(fingerprint.call).to eq(before)
      expect(said).to include("SSPs whose SA-15(13) statement still carries SA-15(12)'s text: 1",
                              "  SSP ##{stale.id}: Invented Example SSP")
    end
  end

  it "touches no catalog that is not NIST's Rev 5, whatever it is called" do
    lookalike = released.deep_dup
    lookalike["catalog"]["uuid"] = "0e9c2c1b-0000-4000-8000-00000000c0de"
    lookalike["catalog"]["metadata"]["title"] = "Invented Agency copy of NIST SP 800-53 Rev 5"
    catalog = import(lookalike, name: "lookalike.json")
    before = state(catalog)

    migration.up

    expect(state(catalog)).to eq(before)
    expect(catalog.reload.metadata_extra).not_to have_key("nist_develop_patch")
  end

  it "finds nothing to change on a catalog imported from the fixed file" do
    catalog = import(develop)
    before = state(catalog)

    migration.up

    expect(state(catalog)).to eq(before)
  end
end
