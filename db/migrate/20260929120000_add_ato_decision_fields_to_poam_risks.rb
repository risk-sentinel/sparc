# frozen_string_literal: true

# #1154 — the AO-decision fields a POA&M risk carries, exported as the SPARC
# namespace props sparc-horizon reads:
#
#   poam_risks.blocks_ato         -> `blocks-ato`        (true / false)
#   poam_risks.condition_expires  -> `condition-expires` (YYYY-MM-DD)
#   poam_risks.reopen_trigger     -> `trigger`           (score<0.85, blockers>=1)
#
# All nullable with no default and no backfill. `blocks_ato` in particular must
# not default to false: an undecided risk is not a risk someone decided does not
# block the ATO, and a default would publish that claim for every existing row.
# Guarded per the Migration Safety Rules so a partial run can be re-run.
class AddAtoDecisionFieldsToPoamRisks < ActiveRecord::Migration[8.1]
  def up
    add_column :poam_risks, :blocks_ato, :boolean unless column_exists?(:poam_risks, :blocks_ato)
    add_column :poam_risks, :condition_expires, :date unless column_exists?(:poam_risks, :condition_expires)
    add_column :poam_risks, :reopen_trigger, :string unless column_exists?(:poam_risks, :reopen_trigger)
  end

  def down
    remove_column :poam_risks, :reopen_trigger, if_exists: true
    remove_column :poam_risks, :condition_expires, if_exists: true
    remove_column :poam_risks, :blocks_ato, if_exists: true
  end
end
