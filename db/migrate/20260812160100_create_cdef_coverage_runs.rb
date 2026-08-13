# #904 — a saved coverage analysis.
#
# ── What is deliberately absent from these tables ─────────────────────────
#
# The uploaded Terraform. All of it.
#
# A .tfstate carries plaintext secrets, so the upload is parsed in-request and
# discarded; it is never attached to a record and never written to Active
# Storage. What persists is the derived census: which services were found, how
# many resources of which TYPE names, and the verdict for each. A resource type
# (`aws_db_instance`) names no account, region or secret. A resource value does,
# and none is stored.
#
# `source_files` records what was analysed as name + SHA-256 only, so a later
# run can say "this is the same state you analysed before" without the content
# having been kept.
#
# Saving is an explicit second step, not a side effect of analysing (#904): an
# operator can run the wizard, read the report, export it, and persist nothing.
class CreateCdefCoverageRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :cdef_coverage_runs do |t|
      # Optional: the wizard can be run to answer a question without committing
      # the answer to a boundary.
      t.references :authorization_boundary, foreign_key: { on_delete: :nullify }, null: true, index: true
      t.references :created_by_user, foreign_key: { to_table: :users, on_delete: :nullify },
                   null: true, index: true

      # Provenance of the analysis itself, stamped server-side like evidence
      # collection (#934, AU-10).
      t.string :created_by, null: true
      t.datetime :analyzed_at, null: false

      # [{filename:, digest:, format:, resource_count:}] — never content.
      t.jsonb :source_files, default: [], null: false
      # [{resource_type:, count:}] for types no rule matched.
      t.jsonb :unmapped_resource_types, default: [], null: false

      t.integer :adopt_count, default: 0, null: false
      t.integer :keep_custom_count, default: 0, null: false
      t.integer :needs_custom_count, default: 0, null: false
      t.integer :stale_custom_count, default: 0, null: false

      t.string :uuid, default: -> { "gen_random_uuid()" }, null: false
      t.timestamps
    end

    add_index :cdef_coverage_runs, :uuid, unique: true
    add_index :cdef_coverage_runs, :analyzed_at

    create_table :cdef_coverage_results do |t|
      t.references :cdef_coverage_run, foreign_key: { on_delete: :cascade }, null: false, index: true
      t.string :service_key, null: false
      t.string :verdict, null: false
      t.integer :resource_count, default: 0, null: false
      # Type NAMES only — see the note above on why these are safe to keep.
      t.string :resource_types, default: [], null: false, array: true
      # True when the service key was inferred from a resource type rather than
      # matched by a rule, so a reader can tell a derived name from a known one.
      t.boolean :inferred, default: false, null: false
      t.jsonb :cdef_documents, default: [], null: false
      t.timestamps
    end

    add_index :cdef_coverage_results, [ :cdef_coverage_run_id, :service_key ], unique: true,
              name: "index_cdef_coverage_results_on_run_and_service"
    add_index :cdef_coverage_results, :verdict
  end
end
