# frozen_string_literal: true

# #809 — amendment approval flow. A disposition is created by `decided_by` and
# separately approved by `approved_by` (both bound in the signature). approval_status
# gates whether the amendment is applied. valid_until is the ODP-timeline result
# (§5): the amendment is valid only within the remediation window or while an
# active POA&M covers the control.
class AddApprovalToFindingDispositions < ActiveRecord::Migration[8.1]
  def change
    add_column :finding_dispositions, :approval_status, :string, default: "draft", null: false
    add_column :finding_dispositions, :approved_by, :string
    add_column :finding_dispositions, :approved_at, :datetime
    add_column :finding_dispositions, :valid_until, :datetime
    add_index :finding_dispositions, :approval_status
  end
end
