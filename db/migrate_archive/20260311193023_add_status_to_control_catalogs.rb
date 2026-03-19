class AddStatusToControlCatalogs < ActiveRecord::Migration[8.1]
  def change
    add_column :control_catalogs, :status, :string, default: "completed", null: false
    add_column :control_catalogs, :error_message, :text
    add_column :control_catalogs, :original_filename, :string
  end
end
