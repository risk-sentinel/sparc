class AddProjectFkToUserRoles < ActiveRecord::Migration[8.1]
  def change
    add_index :user_roles, :project_id
    add_foreign_key :user_roles, :projects, column: :project_id, on_delete: :cascade
  end
end
