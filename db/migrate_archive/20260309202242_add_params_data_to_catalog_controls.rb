class AddParamsDataToCatalogControls < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_controls, :params_data, :jsonb, default: []
  end
end
