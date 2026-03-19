# frozen_string_literal: true

class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :name, null: false
      t.text :description
      t.text :address
      t.string :contact_person
      t.string :contact_email
      t.string :status, null: false, default: "active"
      t.timestamps
    end

    add_index :organizations, :uuid, unique: true
    add_index :organizations, :name, unique: true
    add_index :organizations, :status
  end
end
