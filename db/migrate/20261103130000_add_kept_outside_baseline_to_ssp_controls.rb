# frozen_string_literal: true

# #1330 — a control an SSP keeps, for its answers, after its baseline was
# changed to one that does not select it. Marked by the change itself, so the
# OSCAL export leaves out exactly what the change kept and nothing else (an
# imported SSP's controls outside its baseline are not affected).
class AddKeptOutsideBaselineToSspControls < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:ssp_controls, :kept_outside_baseline)

    add_column :ssp_controls, :kept_outside_baseline, :boolean, default: false, null: false
  end

  def down
    remove_column :ssp_controls, :kept_outside_baseline if column_exists?(:ssp_controls, :kept_outside_baseline)
  end
end
