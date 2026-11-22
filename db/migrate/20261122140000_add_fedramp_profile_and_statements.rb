# frozen_string_literal: true

# #1390 — FedRAMP becomes something a boundary turns on, and the boundary
# records its answer to each FedRAMP rule and Key Security Indicator, which
# its Security Decision Record carries (SDR-CSO-FRR, SDR-CSX-KSI).
#
#   authorization_boundaries.fedramp_enabled      FedRAMP applies to this system;
#                                                 its FedRAMP features show only then
#   authorization_boundaries.fedramp_sdr_version  counts each change to the
#                                                 statements (the SDR's metadata.version)
#   fedramp_statements                            one row per boundary and rule or KSI:
#                                                 status, implementation, validation,
#                                                 assessment; for a KSI also its tests and
#                                                 evidence
#
# A boundary that already uses FedRAMP (an overview address, overview fields
# or a FedRAMP evaluation) is switched on, so nothing it has disappears.
#
# Idempotent (docs/dev/issue_rules.md, migration rules 1–6).
class AddFedrampProfileAndStatements < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:authorization_boundaries, :fedramp_enabled)
      add_column :authorization_boundaries, :fedramp_enabled, :boolean, null: false, default: false
    end
    unless column_exists?(:authorization_boundaries, :fedramp_sdr_version)
      add_column :authorization_boundaries, :fedramp_sdr_version, :integer, null: false, default: 0
    end

    create_table :fedramp_statements, if_not_exists: true do |t|
      t.references :authorization_boundary, null: false, foreign_key: true, index: true
      t.string :kind, null: false
      t.string :rule_id, null: false
      t.string :status
      t.text :implementation
      t.text :validation
      t.text :assessment
      t.jsonb :tests, null: false, default: []
      t.jsonb :evidence, null: false, default: []
      t.references :updated_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.timestamps
    end
    unless index_exists?(:fedramp_statements, %i[authorization_boundary_id kind rule_id], unique: true)
      add_index :fedramp_statements, %i[authorization_boundary_id kind rule_id], unique: true,
                                                                             name: "idx_fedramp_statements_unique"
    end

    execute <<~SQL.squish
      UPDATE authorization_boundaries SET fedramp_enabled = TRUE
      WHERE fedramp_enabled = FALSE
        AND (NULLIF(fedramp_package_overview_uri, '') IS NOT NULL
             OR fedramp_package <> '{}'::jsonb
             OR fedramp_contacts <> '[]'::jsonb
             OR id IN (SELECT authorization_boundary_id FROM fedramp_vulnerability_evaluations))
    SQL
  end

  def down
    drop_table :fedramp_statements, if_exists: true
    %i[fedramp_sdr_version fedramp_enabled].each do |name|
      remove_column :authorization_boundaries, name if column_exists?(:authorization_boundaries, name)
    end
  end
end
