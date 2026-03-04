class CreateCatalogControls < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_controls do |t|
      t.references :control_family, null: false, foreign_key: true
      t.string :control_id, null: false
      t.string :title
      t.text :description
      t.string :priority
      t.string :baseline_impact

      t.timestamps
    end

    add_index :catalog_controls, [ :control_family_id, :control_id ], unique: true
    add_index :catalog_controls, :control_id
  end
end
