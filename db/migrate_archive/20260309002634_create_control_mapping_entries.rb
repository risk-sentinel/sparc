class CreateControlMappingEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :control_mapping_entries do |t|
      t.string     :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :control_mapping, null: false, foreign_key: true
      t.string     :source_control_id, null: false
      t.string     :source_type, default: "control"
      t.string     :target_control_id, null: false
      t.string     :target_type, default: "control"
      t.string     :relationship, null: false
      t.string     :matching_rationale
      t.text       :remarks
      t.integer    :row_order, default: 0
      t.timestamps
    end

    add_index :control_mapping_entries, :uuid, unique: true
    add_index :control_mapping_entries, [ :control_mapping_id, :row_order ]
    add_index :control_mapping_entries,
              [ :control_mapping_id, :source_control_id, :target_control_id ],
              unique: true, name: "idx_mapping_entries_unique_pair"
  end
end
