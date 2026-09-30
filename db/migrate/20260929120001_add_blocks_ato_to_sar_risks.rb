# frozen_string_literal: true

# #1154 — `blocks-ato` on an assessment-results risk.
#
# The contract puts `blocks-ato` on "a risk", and a SAR carries risks of its own
# (`sar_risks`), which are what an AO reads when deciding. Whether a finding
# blocks the authorization is a judgement made on the assessment, so the SAR
# risk gets the column too.
#
# `condition-expires` and `trigger` do NOT come here. They are conditions ON an
# AO decision — when the decision lapses and what reopens it — and that
# decision, with its conditions, is tracked in the POA&M, not in the assessor's
# point-in-time result. A SAR risk that arrives carrying them keeps them as
# issued in its props (they are still validated on export); SPARC just does not
# model them as SAR data.
#
# Nullable, no default, no backfill: nil is "not decided", which is not false.
class AddBlocksAtoToSarRisks < ActiveRecord::Migration[8.1]
  def up
    add_column :sar_risks, :blocks_ato, :boolean unless column_exists?(:sar_risks, :blocks_ato)
  end

  def down
    remove_column :sar_risks, :blocks_ato, if_exists: true
  end
end
