# frozen_string_literal: true

require "rails_helper"

# A freshly seeded demo SSP must have the statement structure its catalog
# defines, not one statement per control.
#
# The demo SSPs are imported from OSCAL that holds a single statement per
# control. Instances that predate #1100 got the sub-parts from a one-time
# migration; a fresh install never runs it, so its demo SSPs had zero controls
# with more than one statement, and the six statement-authoring checks in the
# UI smoke suite skipped on exactly the instance the release gate builds.
#
# rspec never seeds the demo estate, so nothing here could see that. This runs
# the seed file against an SSP shaped like the freshly imported one.
RSpec.describe "db/seeds/ssp_statement_parts.rb — demo SSPs get their sub-part statements" do
  let(:seed_path) { Rails.root.join("db/seeds/ssp_statement_parts.rb") }
  let(:name)      { "ACME HR Portal — SSP (NIST SP 800-53 Rev 5, Low)" }

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

  # What the importer leaves: the single flattened statement.
  let(:flattened) do
    { "catalog" => { "controls" => [ { "id" => "ac-1", "title" => "Policy",
                                       "parts" => [ { "id" => "ac-1_smt", "name" => "statement",
                                                      "prose" => "flattened" } ] } ] } }
  end
  let(:profile) { create(:profile_document, control_catalog: catalog, resolved_catalog_json: flattened) }
  let(:ssp)     { create(:ssp_document, name: name, profile_document: profile) }
  let(:control) { ssp.ssp_controls.find_by(control_id: "ac-1") }

  def run_seed
    original = $stdout
    $stdout = StringIO.new
    load seed_path
  ensure
    $stdout = original
  end

  def flagged?(document)
    document.reload.import_metadata&.dig(CatalogPartExtractorService::REASSOCIATION_FLAG) ==
      CatalogPartExtractorService::REASSOCIATION_VALUE
  end

  before do
    ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy").tap do |c|
      c.ssp_control_statements.create!(statement_id: "ac-1_smt", row_order: 0, uuid: SecureRandom.uuid,
                                       implementation_prose: "written by an author")
    end
  end

  it "adds the catalog's sub-part statements to a demo SSP that has one per control" do
    expect(control.ssp_control_statements.count).to eq(1)

    run_seed

    expect(control.ssp_control_statements.reload.pluck(:statement_id))
      .to match_array(%w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.b])
  end

  it "leaves the statement that was already there, and its prose, alone" do
    run_seed

    expect(control.ssp_control_statements.find_by(statement_id: "ac-1_smt").implementation_prose)
      .to eq("written by an author")
  end

  it "is safe to run again: nothing is added and the document is not flagged" do
    run_seed
    count = control.ssp_control_statements.reload.count

    run_seed

    expect(control.ssp_control_statements.reload.count).to eq(count)
    expect(flagged?(ssp)).to be(false),
      "a complete document was flagged as needing re-association, which puts a warning on its page"
  end

  it "does not touch an SSP that is not one of the demo documents" do
    other = create(:ssp_document, name: "A customer's own SSP", profile_document: profile)
    other.ssp_controls.create!(control_id: "ac-1", title: "Policy").tap do |c|
      c.ssp_control_statements.create!(statement_id: "ac-1_smt", row_order: 0, uuid: SecureRandom.uuid)
    end

    run_seed

    expect(other.ssp_controls.first.ssp_control_statements.count).to eq(1)
  end
end
