# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260817120000_remove_orphaned_aws_labs_cdef_documents.rb")

# #939 — the cleanup for CdefDocument shells left behind by failed AWS Labs
# imports.
#
# The migration is deferred, so this drives `remove_orphaned_shells` directly
# rather than through `up` (which would only enqueue it).
#
# The rows carry no marker identifying them, so they are matched by a
# conjunction of seven conditions. Most of what matters here is what the
# migration must NOT delete: each example below removes exactly one condition
# from an otherwise-matching row and asserts it survives. A deletion this
# heuristic is only as safe as the narrowness of its predicate, and the
# narrowness is only real if it is pinned.
RSpec.describe RemoveOrphanedAwsLabsCdefDocuments do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  # The exact shape a failed import left behind.
  def orphan(name: "AWS s3 (oscal 1.1.2)", **overrides)
    CdefDocument.create!(
      {
        name: name,
        status: "processing",
        cdef_type: "custom",
        file_type: "json",
        lifecycle_status: "published",
        globally_available: true
      }.merge(overrides)
    )
  end

  it "removes an orphaned shell" do
    doc = orphan

    expect { migration.remove_orphaned_shells }
      .to change { CdefDocument.unscoped.where(id: doc.id).count }.from(1).to(0)
  end

  it "removes several, and reports how many" do
    orphan(name: "AWS s3 (oscal 1.1.2)")
    orphan(name: "AWS ec2 (oscal 1.1.2)")
    orphan(name: "AWS glue (oscal 1.2.1)")

    expect(migration.remove_orphaned_shells).to eq(3)
  end

  it "is idempotent — a second run is a no-op" do
    orphan
    migration.remove_orphaned_shells

    expect(migration.remove_orphaned_shells).to eq(0)
  end

  it "is a no-op on an instance that never ran the ingest" do
    create(:cdef_document, name: "Hand authored thing", status: "completed")

    expect(migration.remove_orphaned_shells).to eq(0)
  end

  describe "what it refuses to touch" do
    it "spares a completed document" do
      doc = orphan(status: "completed")

      migration.remove_orphaned_shells

      expect(CdefDocument.unscoped.where(id: doc.id)).to exist
    end

    it "spares a document that has controls" do
      doc = orphan
      CdefControl.create!(cdef_document: doc, control_id: "ac-1", title: "x", row_order: 0)

      migration.remove_orphaned_shells

      expect(CdefDocument.unscoped.where(id: doc.id)).to exist
    end

    it "spares a correctly-tagged AWS Labs document" do
      doc = orphan(import_metadata: { "source_type" => "aws_labs" })

      migration.remove_orphaned_shells

      expect(CdefDocument.unscoped.where(id: doc.id)).to exist
    end

    it "spares a user's clone" do
      source = create(:cdef_document)
      doc = orphan(cloned_from_id: source.id)

      migration.remove_orphaned_shells

      expect(CdefDocument.unscoped.where(id: doc.id)).to exist
    end

    # The interactive upload path has a superficially similar create-then-parse
    # shape, but it attaches the file first and moves to "failed" — a visible,
    # retryable state holding the user's own content. Deleting one of those
    # would be data loss, so the attachment is a hard exclusion.
    it "spares a stuck interactive upload, because it has a file attached" do
      doc = orphan(name: "AWS s3 (oscal 1.1.2)")
      doc.file.attach(
        io: StringIO.new('{"component-definition":{}}'),
        filename: "uploaded.json",
        content_type: "application/json"
      )

      migration.remove_orphaned_shells

      expect(CdefDocument.unscoped.where(id: doc.id)).to exist
    end

    it "spares a document whose name is not the shape derive_name produces" do
      doc = orphan(name: "Quarterly review notes")

      migration.remove_orphaned_shells

      expect(CdefDocument.unscoped.where(id: doc.id)).to exist
    end
  end

  # Guards the `NOT IN (subquery)` trap: a single NULL in the subquery makes the
  # whole predicate NULL, so the migration would silently match nothing and
  # report a clean run while every orphan survived.
  it "still finds orphans when unrelated child rows exist" do
    other = create(:cdef_document)
    CdefControl.create!(cdef_document: other, control_id: "ac-1", title: "x", row_order: 0)
    doc = orphan

    expect(migration.remove_orphaned_shells).to eq(1)
    expect(CdefDocument.unscoped.where(id: doc.id)).not_to exist
    expect(CdefDocument.unscoped.where(id: other.id)).to exist
  end
end
