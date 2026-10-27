# frozen_string_literal: true

# #1312 — give each statement item of an existing SSP the status, origination,
# responsible roles and expected completion its control recorded once for all
# of them. SspControlFieldCarryDown is the mapping (Will Not Implement →
# alternative, Deferred → planned, …); what does not map is noted on the
# control, so nothing is lost.
#
# The control-level rows are left in place, unread, until v1.18.0: an upgrade
# can be rolled back to v1.17.4 and find them as they were.
#
# Idempotent: an item's own value is never overwritten and the note is written
# once, so a re-run changes nothing. One transaction per control.
class CarrySspControlFieldsToItems < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      totals = Hash.new(0)
      SspDocument.find_each do |document|
        result = SspControlFieldCarryDown.new(document).carry!
        totals[:documents] += 1 if result.controls.positive?
        totals[:controls] += result.controls
        totals[:items] += result.items
        totals[:noted] += result.noted
      end
      Rails.logger.info("[CarrySspControlFieldsToItems] #{totals.to_h}")
    end
  end

  def down
    # The control-level rows were never changed, so there is nothing to undo.
  end
end
