class PadCatalogControlIds < ActiveRecord::Migration[8.1]
  # Pad single-digit control numbers so they sort correctly:
  #   "AC-1"  → "AC-01"   "AC-10" unchanged   "AC-9" → "AC-09"
  # Only the base number is padded; sub-part suffixes ("AC-01a", "AC-01a.1") are left alone.
  #
  # This migration is idempotent — already-padded IDs ("AC-01") are skipped.

  PATTERN = /\A([A-Z]+-?)(\d+)\z/

  def up
    pad_table(:catalog_controls, :control_id)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Unpadding control IDs is not supported — cannot distinguish AC-01 (original) from AC-1 (padded)."
  end

  private

  def pad_table(table, column)
    ids = connection.select_all("SELECT id, #{column} FROM #{table}").rows
    ids.each do |id, ctrl_id|
      next if ctrl_id.blank?
      padded = ctrl_id.sub(PATTERN) { "#{$1}#{$2.rjust(2, '0')}" }
      next if padded == ctrl_id
      connection.execute(
        "UPDATE #{table} SET #{column} = #{connection.quote(padded)} WHERE id = #{id}"
      )
    end
  end
end
