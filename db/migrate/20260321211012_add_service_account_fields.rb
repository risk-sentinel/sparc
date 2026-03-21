# NIST: AC-2 (account management), AC-3 (endpoint scoping),
#       AC-17 (CIDR restrictions), IA-4 (identifier lifecycle),
#       IA-5 (authenticator management)
class AddServiceAccountFields < ActiveRecord::Migration[8.1]
  def change
    # Service account ownership and lifecycle
    add_column :users, :owner_id, :bigint, null: true
    add_column :users, :disabled_at, :datetime
    add_column :users, :disabled_reason, :string
    add_foreign_key :users, :users, column: :owner_id
    add_index :users, :owner_id

    # Token endpoint scoping and CIDR restrictions
    add_column :api_tokens, :allowed_endpoints, :jsonb, default: []
    add_column :api_tokens, :allowed_cidrs, :jsonb, default: []
    add_column :api_tokens, :created_by_id, :bigint
    add_foreign_key :api_tokens, :users, column: :created_by_id
    add_index :api_tokens, :created_by_id
  end
end
