class CreateControlBackMatterLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :control_back_matter_links do |t|
      t.string  :linkable_type, null: false
      t.bigint  :linkable_id,   null: false
      t.references :back_matter_resource, null: false, foreign_key: true

      t.timestamps
    end

    add_index :control_back_matter_links,
              [ :linkable_type, :linkable_id, :back_matter_resource_id ],
              unique: true,
              name: "idx_control_back_matter_links_unique"

    add_index :control_back_matter_links,
              [ :linkable_type, :linkable_id ],
              name: "idx_control_back_matter_links_linkable"
  end
end
