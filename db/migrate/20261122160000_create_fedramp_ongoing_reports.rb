# frozen_string_literal: true

# #1390 — a boundary's FedRAMP Ongoing Certification Reports (CCM-OCR-AVL).
#
#   authorization_boundaries.fedramp_active_agencies  the agencies directly using
#                                                     the service (activeAgencies)
#   fedramp_ongoing_reports                           each report issued: its
#                                                     period, the recommendations
#                                                     typed for it, and the
#                                                     document as issued with its
#                                                     SHA-256. Never changed or
#                                                     deleted
#
# Idempotent (docs/dev/issue_rules.md, migration rules 1–6).
class CreateFedrampOngoingReports < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:authorization_boundaries, :fedramp_active_agencies)
      add_column :authorization_boundaries, :fedramp_active_agencies, :jsonb, null: false, default: []
    end

    create_table :fedramp_ongoing_reports, if_not_exists: true do |t|
      t.references :authorization_boundary, null: false, foreign_key: true, index: true
      t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.date :period_from, null: false
      t.date :period_to, null: false
      t.jsonb :recommendations, null: false, default: []
      t.jsonb :document, null: false
      t.string :sha256, null: false
      t.references :issued_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.timestamps
    end
    add_index :fedramp_ongoing_reports, :uuid, unique: true, if_not_exists: true
  end

  def down
    drop_table :fedramp_ongoing_reports, if_exists: true
    remove_column :authorization_boundaries, :fedramp_active_agencies if column_exists?(:authorization_boundaries, :fedramp_active_agencies)
  end
end
