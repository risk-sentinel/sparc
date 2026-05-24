# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260523200000_restore_cloned_from_id_on_cdef_documents.rb")

# Issue #537 — verifies the recovery migration adds `cloned_from_id` when
# missing and is a no-op on already-correct DBs.
RSpec.describe RestoreClonedFromIdOnCdefDocuments do
  let(:migration) { described_class.new }
  let(:conn)      { ActiveRecord::Base.connection }

  around do |ex|
    conn.transaction do
      ex.run
      raise ActiveRecord::Rollback
    end
  end

  context "when cloned_from_id is missing (prod state)" do
    before do
      conn.execute("DROP INDEX IF EXISTS idx_cdef_docs_aws_labs_source_unique")
      conn.execute("ALTER TABLE cdef_documents DROP COLUMN IF EXISTS cloned_from_id CASCADE")
      CdefDocument.reset_column_information
    end

    it "adds the column, the FK, and the partial unique index" do
      expect { migration.migrate(:up) }.not_to raise_error

      expect(conn.column_exists?(:cdef_documents, :cloned_from_id)).to be(true)
      expect(conn.index_exists?(:cdef_documents, :cloned_from_id)).to be(true)

      idx = conn.select_value(
        "SELECT 1 FROM pg_indexes WHERE indexname = 'idx_cdef_docs_aws_labs_source_unique'"
      )
      expect(idx).to eq(1)
    end
  end

  context "when cloned_from_id already exists (correct state)" do
    it "is a no-op and does not raise" do
      expect(conn.column_exists?(:cdef_documents, :cloned_from_id)).to be(true)
      expect { migration.migrate(:up) }.not_to raise_error
      expect(conn.column_exists?(:cdef_documents, :cloned_from_id)).to be(true)
    end
  end
end
