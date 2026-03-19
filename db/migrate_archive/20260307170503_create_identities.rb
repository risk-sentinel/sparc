# frozen_string_literal: true

class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string     :provider,    null: false
      t.string     :uid,         null: false
      t.string     :email
      t.jsonb      :auth_data,   null: false, default: {}
      t.jsonb      :mfa_data,    null: false, default: {}
      t.datetime   :last_used_at

      t.timestamps
    end

    add_index :identities, [ :provider, :uid ], unique: true
  end
end
