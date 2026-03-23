# NIST: AC-2 (account management), AC-3 (endpoint scoping),
#       AC-17 (CIDR restrictions), IA-4 (identifier lifecycle),
#       IA-5 (authenticator management)
class AddServiceAccountFields < ActiveRecord::Migration[8.1]
  def change
    # Service account ownership and lifecycle
    add_column :users, :owner_id, :bigint, null: true unless column_exists?(:users, :owner_id)
    add_column :users, :disabled_at, :datetime unless column_exists?(:users, :disabled_at)
    add_column :users, :disabled_reason, :string unless column_exists?(:users, :disabled_reason)
    unless foreign_key_exists?(:users, column: :owner_id)
      add_foreign_key :users, :users, column: :owner_id
    end
    add_index :users, :owner_id unless index_exists?(:users, :owner_id)

    # Token endpoint scoping and CIDR restrictions
    add_column :api_tokens, :allowed_endpoints, :jsonb, default: [] unless column_exists?(:api_tokens, :allowed_endpoints)
    add_column :api_tokens, :allowed_cidrs, :jsonb, default: [] unless column_exists?(:api_tokens, :allowed_cidrs)
    add_column :api_tokens, :created_by_id, :bigint unless column_exists?(:api_tokens, :created_by_id)
    unless foreign_key_exists?(:api_tokens, column: :created_by_id)
      add_foreign_key :api_tokens, :users, column: :created_by_id
    end
    add_index :api_tokens, :created_by_id unless index_exists?(:api_tokens, :created_by_id)
  end
end
