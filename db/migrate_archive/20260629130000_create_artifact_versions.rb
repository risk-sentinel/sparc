# frozen_string_literal: true

# #680 — artifact version history. One row per *material* change to an evidence
# artifact (file re-upload, attestation re-review, or status change). Each row
# carries the content-version UUID emitted in OSCAL back-matter, the as-of
# (reviewed) date, and an attester snapshot — the permanent audit trail and the
# delta source for ODP review-cadence checks (#685). Per-version content is
# retained by reference via the `content` Active Storage attachment.
class CreateArtifactVersions < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:artifact_versions)

    create_table :artifact_versions do |t|
      t.references :evidence, null: false,
                   foreign_key: { on_delete: :cascade }, index: true
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string   :fingerprint, null: false
      t.string   :file_hash
      t.jsonb    :attester_snapshot, null: false, default: []
      t.string   :evidence_status
      t.datetime :reviewed_at
      t.string   :change_reason
      t.datetime :superseded_at
      t.timestamps
    end

    add_index :artifact_versions, :uuid, unique: true, if_not_exists: true
    add_index :artifact_versions, [ :evidence_id, :superseded_at ], if_not_exists: true
    add_index :artifact_versions, [ :evidence_id, :fingerprint ], if_not_exists: true
  end
end
