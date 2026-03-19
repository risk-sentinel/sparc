# frozen_string_literal: true

class CreateOrganizationMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_memberships do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false, default: "member"
      t.timestamps
    end

    add_index :organization_memberships, [ :organization_id, :user_id ], unique: true
  end
end
