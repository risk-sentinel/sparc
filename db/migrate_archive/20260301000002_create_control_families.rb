class CreateControlFamilies < ActiveRecord::Migration[8.1]
  def change
    create_table :control_families do |t|
      t.references :control_catalog, null: false, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.integer :sort_order, default: 0

      t.timestamps
    end

    add_index :control_families, [ :control_catalog_id, :code ], unique: true
    add_index :control_families, :code
  end
end
