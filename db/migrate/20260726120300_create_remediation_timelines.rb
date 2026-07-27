# frozen_string_literal: true

# #809 (D3) — admin-provisioned remediation-timeline (SLA) table. When the
# boundary's profile has no ODP remediation value for a control, the amendment
# validity window falls back to this table, keyed by the profile baseline level
# and the NIST criticality of the finding. The Instance Admin manages the rows
# (screen + API); seeded with sensible defaults.
#
# NIST 800-53: SI-2 (flaw remediation cadence), CA-5 (POA&M), RA-3 (risk).
class CreateRemediationTimelines < ActiveRecord::Migration[8.1]
  def change
    create_table :remediation_timelines do |t|
      t.string  :baseline_level, null: false   # Low | Moderate | High
      t.string  :criticality, null: false      # Critical | High | Moderate | Low | Informational | Unknown
      t.integer :days, null: false
      t.string  :updated_by
      t.timestamps
    end
    add_index :remediation_timelines, [ :baseline_level, :criticality ], unique: true
  end
end
