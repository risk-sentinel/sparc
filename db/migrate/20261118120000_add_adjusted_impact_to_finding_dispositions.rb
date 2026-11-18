# frozen_string_literal: true

# #1368 — a riskAdjustment disposition re-rates a finding's impact. hdf-cli
# 3.8.0 requires that override to carry the new impact (0.0–1.0) and no
# status, and SPARC stored no impact, so a boundary holding one could not
# export its HDF amendments. Nullable: only riskAdjustment carries it.
class AddAdjustedImpactToFindingDispositions < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:finding_dispositions, :adjusted_impact)

    add_column :finding_dispositions, :adjusted_impact, :decimal, precision: 3, scale: 2, null: true
  end

  def down
    remove_column :finding_dispositions, :adjusted_impact if column_exists?(:finding_dispositions, :adjusted_impact)
  end
end
