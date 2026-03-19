class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :name, null: false
      t.jsonb :scopes, default: {}
      t.datetime :expires_at
      t.datetime :last_used_at
      t.string :last_used_ip

      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
  end
end
