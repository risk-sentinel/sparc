class AddSlugToConverters < ActiveRecord::Migration[8.1]
  def change
    add_column :converters, :slug, :string
    add_index :converters, :slug, unique: true

    # Backfill existing converters with slugs derived from their names
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE converters
          SET slug = LOWER(REGEXP_REPLACE(REGEXP_REPLACE(name, '[^a-zA-Z0-9\\s-]', '', 'g'), '\\s+', '-', 'g'))
          WHERE slug IS NULL
        SQL
      end
    end
  end
end
