# frozen_string_literal: true

# #1090 — move the risk vocabulary from three levels to five.
#
# `medium` was never a word either NIST SP 800-30 or FedRAMP uses; both work in
# Very Low / Low / MODERATE / High / Very High. The token ends up in an exported
# OSCAL facet value, so the stored data has to move with the vocabulary or an
# export would claim a level that does not exist in the scale it names.
#
# Deferred, per the repo's convention: this runs after boot in a Solid Queue job
# rather than blocking `db:prepare`.
#
# IDEMPOTENT BY CONSTRUCTION. It only ever rewrites rows still holding the old
# token, so a re-run — or a resume after a partial failure — is a no-op rather
# than a second rewrite. Measured before writing: 5 rows carried `medium`
# (3 impact, 2 likelihood) and no sar_risks carried any rating at all.
class NormaliseRiskLevels < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  LEGACY = { "medium" => "moderate" }.freeze

  def up
    defer_data_migration do
      LEGACY.each do |old_value, new_value|
        [
          [ :poam_risks, %i[impact likelihood] ],
          [ :sar_risks,  %i[impact likelihood] ],
          [ :poam_items, %i[impact likelihood risk_level] ]
        ].each do |table, columns|
          next unless table_exists?(table)

          columns.each do |column|
            next unless column_exists?(table, column)

            updated = execute_update(table, column, old_value, new_value)
            say "#{table}.#{column}: #{updated} row(s) #{old_value} -> #{new_value}" if updated.positive?
          end
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def execute_update(table, column, old_value, new_value)
    quoted = connection.quote_table_name(table)
    col    = connection.quote_column_name(column)
    connection.update(
      "UPDATE #{quoted} SET #{col} = #{connection.quote(new_value)} " \
      "WHERE #{col} = #{connection.quote(old_value)}"
    )
  end
end
