class CreateConverterEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :converter_entries do |t|
      t.string     :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :converter, null: false, foreign_key: true
      t.string     :source_id, null: false
      t.string     :target_id, null: false
      t.string     :relationship, default: "intersects"
      t.string     :category
      t.text       :remarks
      t.integer    :row_order, default: 0
      t.timestamps
    end

    add_index :converter_entries, :uuid, unique: true
    add_index :converter_entries, [ :converter_id, :row_order ]
    add_index :converter_entries,
              [ :converter_id, :source_id, :target_id ],
              unique: true, name: "idx_converter_entries_unique_pair"
  end
end
