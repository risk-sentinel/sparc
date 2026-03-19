class CreateControlCatalogs < ActiveRecord::Migration[8.1]
  def change
    create_table :control_catalogs do |t|
      t.string :name, null: false
      t.string :version
      t.text :description
      t.string :source

      t.timestamps
    end

    add_index :control_catalogs, :name
  end
end
