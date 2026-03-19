# frozen_string_literal: true

class CreateUserRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :user_roles do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :role, null: false, foreign_key: { on_delete: :cascade }
      t.bigint     :project_id  # NULL = instance-scoped; set when Projects exist

      t.timestamps
    end

    add_index :user_roles, [ :user_id, :role_id, :project_id ], unique: true, name: "idx_user_roles_unique"
  end
end
