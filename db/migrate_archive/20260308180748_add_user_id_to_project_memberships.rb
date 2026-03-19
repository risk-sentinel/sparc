class AddUserIdToProjectMemberships < ActiveRecord::Migration[8.1]
  def change
    add_reference :project_memberships, :user, null: true, foreign_key: { on_delete: :nullify }
  end
end
