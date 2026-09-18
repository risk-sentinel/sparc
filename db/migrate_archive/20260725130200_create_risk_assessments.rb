# frozen_string_literal: true

# #447 — link target for the `riskAdjustment` HDF override: a lightweight,
# provenance-bearing record that a finding's severity was downgraded, with the
# original/adjusted severities and rationale. Deliberately NOT a full RA-3
# assessment engine — just enough to justify and audit a downgrade.
#
# NIST 800-53: RA-3 (risk assessment), RA-5 (vulnerability scanning).
class CreateRiskAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :risk_assessments do |t|
      t.references :authorization_boundary, null: false, foreign_key: true
      t.references :evidence, foreign_key: true          # optional supporting evidence
      t.string   :title, null: false
      t.string   :original_severity, null: false         # CRITICAL|HIGH|MEDIUM|LOW|INFORMATIONAL
      t.string   :adjusted_severity, null: false         # must rank strictly below original
      t.text     :rationale, null: false
      t.string   :methodology                            # e.g. "CVSS environmental", "NIST 800-30"
      t.string   :assessed_by, null: false
      t.datetime :assessed_at, null: false
      t.datetime :expiration                             # re-assessment cadence
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string   :slug
      t.timestamps
    end

    add_index :risk_assessments, :uuid, unique: true
    add_index :risk_assessments, :slug, unique: true
  end
end
