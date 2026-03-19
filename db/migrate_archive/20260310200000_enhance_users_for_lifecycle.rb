# frozen_string_literal: true

# Add UUID for audit traceability, deleted_at for soft-delete tracking,
# and inactive_reason for deactivation context.
class EnhanceUsersForLifecycle < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :uuid, :string, null: false, default: -> { "gen_random_uuid()" }
    add_column :users, :deleted_at, :datetime
    add_column :users, :inactive_reason, :string

    add_index :users, :uuid, unique: true
    add_index :users, :deleted_at
  end
end
