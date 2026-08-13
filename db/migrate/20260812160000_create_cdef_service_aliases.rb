# #904 — the two escape hatches the reference implementation proved necessary,
# moved out of hardcoded Python constants and into operator-editable data.
#
# `sparc-iac/oscal/scripts/state_cdef_coverage.py` carries two literals:
#
#   CUSTOM_ALIAS  a custom CDEF's filename does not always match the analyser's
#                 service key — `ecs-fargate` is `ecs`, `secrets` is
#                 `secretsmanager`, `vpc-networking` is `vpc`.
#   ALWAYS_KEEP   some components legitimately hold a CDEF but never appear in
#                 Terraform state at all — the nginx sidecar, the CI/CD
#                 pipeline. Without an allowlist they are false-flagged
#                 STALE-CUSTOM on every single run.
#
# Both are deployment-specific facts about one operator's CDEF library, so
# neither belongs in application code. A row here is a small, auditable
# assertion: "this CDEF covers that service", or "this CDEF is expected to be
# absent from infrastructure".
#
# `cdef_document_id` is nullable so an ALWAYS_KEEP entry can name a service key
# that has no CDEF in this instance yet.
class CreateCdefServiceAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :cdef_service_aliases do |t|
      t.references :cdef_document, foreign_key: { on_delete: :cascade }, null: true, index: true
      t.string :service_key, null: false
      t.boolean :always_keep, default: false, null: false
      t.text :note
      t.timestamps
    end

    # One assertion per (CDEF, service) pair. A CDEF may legitimately cover more
    # than one service, so the uniqueness is on the pair rather than either side.
    add_index :cdef_service_aliases, [ :cdef_document_id, :service_key ], unique: true,
              name: "index_cdef_service_aliases_on_document_and_service"
    add_index :cdef_service_aliases, :service_key
  end
end
