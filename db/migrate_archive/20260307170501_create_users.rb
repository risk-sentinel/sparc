# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :email,               null: false
      t.string   :password_digest
      t.string   :display_name
      t.string   :first_name
      t.string   :last_name
      t.string   :avatar_url
      t.string   :status,              null: false, default: "active"
      t.boolean  :admin,               null: false, default: false
      t.datetime :last_sign_in_at
      t.string   :last_sign_in_ip
      t.integer  :sign_in_count,       null: false, default: 0
      t.datetime :password_changed_at
      t.boolean  :must_reset_password, null: false, default: false

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :status
  end
end
