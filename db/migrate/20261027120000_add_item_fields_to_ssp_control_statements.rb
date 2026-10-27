# frozen_string_literal: true

# #1312 — each statement item an SSP answers records its own implementation
# status, control origination and expected completion. They were recorded once
# per control (`ssp_control_fields`), so a control whose items were partly
# implemented and partly planned could not say so.
#
#   implementation_status  OSCAL `implementation-status` state: implemented,
#                          partial, planned, alternative, not-applicable
#   control_origination    OSCAL `control-origination` values, one or more: an
#                          item partly inherited carries `inherited` and this
#                          system's own origination
#   expected_completion    when a planned item is expected to be in place
#
# Nullable, no default on the scalar columns: an item nobody has answered has
# no status, and a default would read as an author's decision. Existing values
# are carried down from the control by a deferred data migration
# (CarrySspControlFieldsToItems).
class AddItemFieldsToSspControlStatements < ActiveRecord::Migration[8.1]
  def up
    add_column :ssp_control_statements, :implementation_status, :string unless column_exists?(:ssp_control_statements, :implementation_status)
    add_column :ssp_control_statements, :control_origination, :jsonb, default: [], null: false unless column_exists?(:ssp_control_statements, :control_origination)
    add_column :ssp_control_statements, :expected_completion, :date unless column_exists?(:ssp_control_statements, :expected_completion)
  end

  def down
    remove_column :ssp_control_statements, :expected_completion, if_exists: true
    remove_column :ssp_control_statements, :control_origination, if_exists: true
    remove_column :ssp_control_statements, :implementation_status, if_exists: true
  end
end
