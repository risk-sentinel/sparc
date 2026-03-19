class AddLabelAndSortIdToCatalogControls < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_controls, :label, :string
    add_column :catalog_controls, :sort_id, :string
  end
end
