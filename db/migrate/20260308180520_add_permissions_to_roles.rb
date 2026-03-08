class AddPermissionsToRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :roles, :permissions, :jsonb, default: {}, null: false
  end
end
