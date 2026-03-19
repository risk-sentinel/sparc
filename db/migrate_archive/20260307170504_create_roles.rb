# frozen_string_literal: true

class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.string  :name,         null: false
      t.string  :display_name, null: false
      t.string  :scope,        null: false, default: "instance"
      t.text    :description
      t.integer :sort_order,   null: false, default: 0

      t.timestamps
    end

    add_index :roles, :name, unique: true
  end
end
