# frozen_string_literal: true

require "rails_helper"

# #1089 — a component definition describes a component and the controls it
# satisfies, so it is usable under any number of baselines (owner: CDEF 1:n
# profiles, 1:n SSPs). It belonged to at most one, and reuse meant cloning it.
# The links are the truth; `profile_document_id` stays until v1.18.0 as a mirror
# of one linked baseline, so the lineage check and a rollback still find one.
RSpec.describe CdefDocument, "used under many baselines (#1089)" do
  let(:cdef) { create(:cdef_document) }
  let(:moderate) { create(:profile_document, name: "Moderate", lifecycle_status: "published") }
  let(:high) { create(:profile_document, name: "High", lifecycle_status: "published") }

  def control!(id, source: nil)
    create(:cdef_control, cdef_document: cdef, control_id: id, implementation_source: source)
  end

  describe "links" do
    it "serves several baselines, the first linked mirrored in the column" do
      cdef.link_profile!(moderate)
      cdef.link_profile!(high)

      expect(cdef.reload.profile_documents).to contain_exactly(moderate, high)
      expect(cdef.profile_document).to eq(moderate)
      expect(moderate.cdef_documents).to include(cdef)
      expect(high.cdef_documents).to include(cdef)
    end

    it "links whatever sets the column, so every existing write path keeps working" do
      cdef.update!(profile_document: moderate)
      cdef.update!(profile_document: high)

      expect(cdef.reload.profile_documents).to contain_exactly(moderate, high)
    end

    it "moves the mirror to another linked baseline when its own is removed" do
      cdef.link_profile!(moderate)
      cdef.link_profile!(high)

      cdef.unlink_profile!(moderate)
      expect(cdef.reload).to have_attributes(profile_document: high)
      expect(cdef.profile_documents).to eq([ high ])

      cdef.unlink_profile!(high)
      expect(cdef.reload.profile_document).to be_nil
      expect(cdef.profile_documents).to be_empty
    end

    it "unlinks what a cleared column named" do
      cdef.link_profile!(moderate)
      cdef.link_profile!(high)
      cdef.update!(profile_document: nil)

      expect(cdef.reload.profile_documents).to eq([ high ])
      expect(cdef.profile_document).to eq(high)
    end

    it "never links the same baseline twice" do
      2.times { cdef.link_profile!(moderate) }
      expect(cdef.cdef_document_profile_documents.count).to eq(1)
    end
  end

  describe "the 'Baseline not set' check" do
    before { control!("ac-2") }

    it "is resolved once any baseline is linked" do
      expect(cdef.reconciliation_blocks_update?).to be(true)
      cdef.link_profile!(high)
      expect(cdef.reload.reconciliation_blocks_update?).to be(false)
    end

    it "is resolved with no baseline when every control names its own source (#1088)" do
      cdef.cdef_controls.update_all(implementation_source: "uuid:#{SecureRandom.uuid}")
      expect(cdef.reload.reconciliation_blocks_update?).to be(false)
    end

    it "lets a published CDEF take another baseline: adding is not re-pointing" do
      cdef.link_profile!(moderate)
      cdef.update_columns(lifecycle_status: "published")
      expect(cdef.reload.rebaselining_published?(profile_document_id: high.id)).to be(false)
    end
  end

  describe "membership" do
    it "is judged against every linked baseline together" do
      moderate.profile_controls.create!(control_id: "ac-2", row_order: 0)
      high.profile_controls.create!(control_id: "ac-2.12", row_order: 0)
      %w[ac-2 ac-2.12 sc-99].each { control!(_1) }

      cdef.link_profile!(moderate)
      expect(cdef.reload.out_of_baseline_control_ids).to contain_exactly("ac-2.12", "sc-99")

      cdef.link_profile!(high)
      expect(cdef.reload.out_of_baseline_control_ids).to eq([ "sc-99" ])
      expect(cdef.membership_authority).to eq(ControlMembership::AUTHORITATIVE)
    end
  end

  describe "the export's control-implementation source" do
    def sources
      JSON.parse(OscalComponentDefinitionExportService.new(cdef.reload).export_unvalidated)
          .dig("component-definition", "components").flat_map { Array(_1["control-implementations"]) }
          .map { _1["source"] }.uniq
    end

    it "stays the baseline each control was built from once another is linked" do
      built = CdefFromProfileService.new(moderate.tap { _1.update!(resolved_catalog_json: catalog_json) }).create
      expect(built.cdef_controls.pluck(:implementation_source).uniq).to eq([ "uuid:#{moderate.uuid}" ])

      built.link_profile!(high)
      exported = JSON.parse(OscalComponentDefinitionExportService.new(built.reload).export_unvalidated)
                     .dig("component-definition", "components").flat_map { Array(_1["control-implementations"]) }
      expect(exported.map { _1["source"] }.uniq).to eq([ "uuid:#{moderate.uuid}" ])
    end

    it "is unchanged by the upgrade's backfill on a CDEF linked the old way" do
      control!("ac-2")
      cdef.update!(profile_document: moderate)
      before = sources

      require Rails.root.join("db/migrate/20261027130100_backfill_cdef_control_sources.rb")
      begin
        DeferredDataMigration.executing!
        BackfillCdefControlSources.new.up
      ensure
        DeferredDataMigration.idle!
      end

      expect(cdef.cdef_controls.pluck(:implementation_source)).to eq([ "uuid:#{moderate.uuid}" ])
      expect(sources).to eq(before)
    end

    def catalog_json
      { "catalog" => { "uuid" => SecureRandom.uuid,
                       "metadata" => { "title" => "Moderate", "version" => "1", "oscal-version" => "1.1.2",
                                       "last-modified" => Time.current.iso8601 },
                       "groups" => [ { "id" => "ac", "class" => "family", "title" => "Access Control",
                                       "controls" => [ { "id" => "ac-2", "class" => "SP800-53", "title" => "Account Management",
                                                         "parts" => [ { "id" => "ac-2_smt", "name" => "statement",
                                                                        "prose" => "Manage accounts." } ] } ] } ] } }
    end
  end

  it "keeps every link on a copy" do
    cdef.link_profile!(moderate)
    cdef.link_profile!(high)
    copy = DocumentDuplicationService.new(cdef.reload).duplicate

    expect(copy.profile_documents).to contain_exactly(moderate, high)
  end

  it "backfills the links from the column on upgrade" do
    cdef.update_columns(profile_document_id: moderate.id)
    CdefDocumentProfileDocument.delete_all
    require Rails.root.join("db/migrate/20261027130000_create_cdef_document_profile_documents.rb")
    ActiveRecord::Migration.suppress_messages { CreateCdefDocumentProfileDocuments.new.up }

    expect(cdef.reload.profile_documents).to eq([ moderate ])
  end
end
