# #707 / #919 — distinguish a grant derived from boundary-roster membership from
# one an administrator assigned deliberately.
#
# Without this, revoking a membership could not tell the two apart and would
# destroy an admin's explicit grant as a side effect of a roster edit.
#
# Schema-only and fast: a defaulted column, so existing rows are correct by
# construction — every UserRole that predates this WAS manually assigned, since
# membership granted nothing at all until now.
class AddSourceToUserRoles < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:user_roles, :source)

    add_column :user_roles, :source, :string, default: "manual", null: false

    add_index :user_roles, :source, if_not_exists: true
  end
end
