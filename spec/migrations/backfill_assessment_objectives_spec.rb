# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260909140000_backfill_assessment_objectives.rb")

# #1114 — the ORDER is the point.
#
# `resolved_catalog_json` is a cache written at publish time. Every profile
# resolved before the resolver fix holds a catalog with no assessment objectives
# in it, so backfilling objectives WITHOUT re-resolving first reads that stale
# cache, finds nothing, and reports success having added nothing — which is
# precisely how #1100's first backfill attempt failed.
RSpec.describe BackfillAssessmentObjectives do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:control) do
    family.catalog_controls.create!(control_id: "ac-1", title: "Policy").tap do |cc|
      [ [ "ac-1_obj",     nil,          "AC-01",       nil,                      0 ],
        [ "ac-1_obj.a",   "ac-1_obj",   "AC-01a.",     nil,                      1 ],
        [ "ac-1_obj.a-1", "ac-1_obj.a", "AC-01a.[01]", "a policy is developed;", 2 ],
        [ "ac-1_obj.b",   "ac-1_obj",   "AC-01b.",     "an official designated;", 3 ] ].each do |pid, parent, label, prose, order|
        cc.catalog_control_parts.create!(part_id: pid, part_name: "assessment-objective",
                                         parent_part_id: parent, label: label, prose: prose,
                                         row_order: order, uuid: SecureRandom.uuid)
      end
    end
  end

  # The STALE shape: a resolved catalog carrying the control but no objectives,
  # which is what every profile published before the resolver fix holds.
  let(:profile) do
    create(:profile_document, control_catalog: catalog, lifecycle_status: "published",
           resolved_catalog_json: {
             "catalog" => { "controls" => [ { "id" => "ac-1", "title" => "Policy",
                                              "parts" => [ { "id" => "ac-1_smt",
                                                             "name" => "statement",
                                                             "prose" => "flattened" } ] } ] }
           })
  end
  let!(:pctrl) { profile.profile_controls.create!(control_id: "ac-1", title: "Policy") }

  let(:sap) { create(:sap_document, profile_document: profile) }
  let!(:sap_control) { sap.sap_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0) }

  it "re-resolves the profile so the catalog carries objectives again" do
    expect(
      ControlObjectiveExtractorService.objectives_for_control(profile.resolved_catalog_json, "ac-1")
    ).to be_empty

    migration.up

    expect(
      ControlObjectiveExtractorService.objectives_for_control(profile.reload.resolved_catalog_json, "ac-1")
    ).not_to be_empty
  end

  it "creates one objective per catalog objective part" do
    expect(sap_control.sap_control_objectives.count).to eq(0)

    migration.up

    ids = sap_control.sap_control_objectives.reload.pluck(:objective_id)
    expect(ids).to include("ac-1_obj.a-1", "ac-1_obj.b")
    expect(sap_control.sap_control_objectives.count).to be > 1
  end

  it "keeps each objective addressable — label, prose and parent" do
    migration.up

    obj = sap_control.sap_control_objectives.reload.find_by(objective_id: "ac-1_obj.a-1")
    expect(obj.label).to eq("AC-01a.[01]")
    expect(obj.prose).to eq("a policy is developed;")
    expect(obj.parent_objective_id).to eq("ac-1_obj.a")
    expect(obj.status).to eq("pending")
  end

  # An assessment already under way must not be disturbed: the assessor's
  # findings live on these rows.
  it "never touches a control whose objectives an assessor has begun" do
    sap_control.sap_control_objectives.create!(
      objective_id: "ac-1_obj.a-1", label: "AC-01a.[01]", prose: "a policy is developed;",
      status: "passing", assessor_name: "A. Assessor", assessor_notes: "Verified",
      row_order: 0, uuid: SecureRandom.uuid
    )

    migration.up

    objectives = sap_control.sap_control_objectives.reload
    expect(objectives.count).to eq(1)
    expect(objectives.first.status).to eq("passing")
    expect(objectives.first.assessor_notes).to eq("Verified")
  end

  it "adds nothing on a second run" do
    migration.up
    before_ids = sap_control.sap_control_objectives.reload.pluck(:objective_id).sort

    expect { migration.up }
      .not_to change { sap_control.sap_control_objectives.reload.pluck(:objective_id).sort }
    expect(before_ids).not_to be_empty
  end

  it "keeps going when one document cannot resolve a catalog" do
    create(:sap_document, profile_document: nil).sap_controls
      .create!(control_id: "au-1", title: "Orphan", row_order: 0)

    expect { migration.up }.not_to raise_error
    expect(sap_control.sap_control_objectives.reload.count).to be > 1
  end
end
