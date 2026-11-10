# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261110120000_clear_invented_profile_priorities.rb")

# #1357 — clears the P1/P2/P3 SPARC derived from baseline breadth, and keeps
# every priority a person, a catalog or an imported file chose. Driven through
# `defer_data_migration` with the executing flag set the way the runner sets
# it, so a body that only registers fails here.
RSpec.describe ClearInventedProfilePriorities do
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

  # What the old derivation gave each: three baselines → P1, two → P2, one → P3.
  let!(:in_three) { create(:catalog_control, control_family: family, control_id: "ac-1", priority: nil, baseline_impact: "LOW, MODERATE, HIGH") }
  let!(:in_two)   { create(:catalog_control, control_family: family, control_id: "ac-2", priority: nil, baseline_impact: "MODERATE, HIGH") }
  let!(:in_one)   { create(:catalog_control, control_family: family, control_id: "ac-3", priority: nil, baseline_impact: "HIGH") }
  let!(:sub)      { create(:catalog_control, control_family: family, control_id: "ac-2.1", priority: nil, baseline_impact: "MODERATE, HIGH") }

  let(:baseline) { create(:profile_document, control_catalog: catalog, lifecycle_status: "in_progress") }

  def control(id, priority, doc: baseline) = doc.profile_controls.create!(control_id: id, title: id, priority: priority)
  def priorities(doc = baseline) = doc.profile_controls.reload.to_h { [ _1.control_id, _1.priority ] }

  it "clears every priority that matches the old derivation" do
    control("ac-1", "P1")
    control("ac-2", "P2")
    control("ac-3", "P3")
    control("ac-2.1", "P2")

    expect(migration.up).to eq(4)
    expect(priorities).to eq("ac-1" => nil, "ac-2" => nil, "ac-3" => nil, "ac-2.1" => nil)
  end

  it "clears them on a published baseline too" do
    baseline.update!(lifecycle_status: "published")
    control("ac-1", "P1")

    migration.up
    expect(priorities).to eq("ac-1" => nil)
  end

  it "keeps a value that differs from the derivation, so someone chose it" do
    control("ac-1", "P3")
    control("ac-3", "P1")

    expect(migration.up).to eq(0)
    expect(priorities).to eq("ac-1" => "P3", "ac-3" => "P1")
  end

  it "keeps a priority the catalog control carries" do
    in_three.update!(priority: "P1")
    control("ac-1", "P1")

    migration.up
    expect(priorities).to eq("ac-1" => "P1")
  end

  it "keeps a priority set inline or in bulk, even when it equals the derivation" do
    control("ac-1", "P1")
    control("ac-2", "P2")
    AuditEvent.log(action: "profile_controls_bulk_edited", subject: baseline,
                   metadata: { control_ids: [ "ac-1" ], priority_changed: true, priority: "P1" })
    # A bulk edit that only linked a resource did not choose a priority.
    AuditEvent.log(action: "profile_controls_bulk_edited", subject: baseline,
                   metadata: { control_ids: [ "ac-2" ], priority_changed: false, priority: nil })

    migration.up
    expect(priorities).to eq("ac-1" => "P1", "ac-2" => nil)
  end

  it "keeps the priority of a control created or saved through its edit form" do
    created = control("ac-1", "P1")
    edited  = control("ac-2", "P2")
    control("ac-3", "P3")
    AuditEvent.log(action: "profile_control_created", subject: created, metadata: { control_id: "ac-1" })
    AuditEvent.log(action: "profile_control_updated", subject: edited, metadata: { control_id: "ac-2" })

    migration.up
    expect(priorities).to eq("ac-1" => "P1", "ac-2" => "P2", "ac-3" => nil)
  end

  it "keeps in a copy the choices recorded on the baseline it was copied from" do
    control("ac-1", "P1")
    AuditEvent.log(action: "profile_controls_bulk_edited", subject: baseline,
                   metadata: { control_ids: [ "ac-1" ], priority_changed: true, priority: "P1" })
    copy = create(:profile_document, control_catalog: catalog)
    control("ac-1", "P1", doc: copy)
    control("ac-2", "P2", doc: copy)
    AuditEvent.log(action: "profile_document_copied", subject: copy, metadata: { source_id: baseline.id })

    migration.up
    expect(priorities(copy)).to eq("ac-1" => "P1", "ac-2" => nil)
  end

  it "keeps in a baseline made by Create from Profile the choices recorded on its source" do
    control("ac-1", "P1")
    control("ac-2", "P2")
    AuditEvent.log(action: "profile_control_updated", subject: baseline.profile_controls.find_by(control_id: "ac-1"),
                   metadata: { control_id: "ac-1" })
    tailored = create(:profile_document, control_catalog: catalog, source_profile_id: baseline.id)
    control("ac-1", "P1", doc: tailored)
    control("ac-2", "P2", doc: tailored)

    migration.up
    expect(priorities(tailored)).to eq("ac-1" => "P1", "ac-2" => nil)
  end

  it "leaves an imported baseline alone" do
    %w[oscal_profile oscal_resolved_profile].each do |format|
      doc = create(:profile_document, control_catalog: catalog, import_metadata: { "format" => format })
      control("ac-1", "P1", doc: doc)

      migration.up
      expect(priorities(doc)).to eq("ac-1" => "P1"), format
    end
  end

  it "keeps a priority it cannot check against a catalog control" do
    control("cm-99", "P3")
    orphan = create(:profile_document, control_catalog: nil)
    control("ac-1", "P1", doc: orphan)

    migration.up
    expect(priorities).to eq("cm-99" => "P3")
    expect(priorities(orphan)).to eq("ac-1" => "P1")
  end

  it "records each baseline's cleared values in one audit event" do
    control("ac-1", "P1")
    control("ac-3", "P3")

    expect { migration.up }.to change { AuditEvent.where(action: "profile_document_updated").count }.by(1)
    event = AuditEvent.where(action: "profile_document_updated").last
    expect(event.subject_id).to eq(baseline.id)
    expect(event.metadata["cleared_priorities"]).to eq("ac-1" => "P1", "ac-3" => "P3")
    expect(event.metadata["issue"]).to eq(1357)
  end

  it "is a no-op the second time" do
    control("ac-1", "P1")
    migration.up

    expect(migration.up).to eq(0)
    expect(AuditEvent.where(action: "profile_document_updated").count).to eq(1)
  end
end
