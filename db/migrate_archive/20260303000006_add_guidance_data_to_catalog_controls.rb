class AddGuidanceDataToCatalogControls < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_controls, :guidance_data, :jsonb, default: {}
  end
end
