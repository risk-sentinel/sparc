class AddAwsLabsProvenanceToCdefDocuments < ActiveRecord::Migration[8.1]
  def change
    # Issue #466 — AWS Labs CDEF runtime ingestion.
    # cloned_from_id supports the copy-to-amend policy: AWS-sourced rows are
    # read-only; users clone them to edit. Self-referential FK is safe because
    # we set null: true and never cascade delete.
    unless column_exists?(:cdef_documents, :cloned_from_id)
      add_reference :cdef_documents,
        :cloned_from,
        null: true,
        foreign_key: { to_table: :cdef_documents }
    end

    # Partial unique index on (import_metadata->>'source_url',
    # import_metadata->>'source_sha') scoped to AWS-sourced rows. Prevents
    # duplicate imports of the same blob content. Multi-expression functional
    # indexes need raw SQL because Rails' add_index parses the expression
    # string and the (a, b) tuple form trips the parser.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE UNIQUE INDEX IF NOT EXISTS idx_cdef_docs_aws_labs_source_unique
            ON cdef_documents ((import_metadata->>'source_url'), (import_metadata->>'source_sha'))
            WHERE import_metadata->>'source_type' = 'aws_labs'
        SQL
      end

      dir.down do
        execute "DROP INDEX IF EXISTS idx_cdef_docs_aws_labs_source_unique"
      end
    end
  end
end
