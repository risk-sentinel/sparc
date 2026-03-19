# frozen_string_literal: true

class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string     :action,     null: false
      t.string     :provider
      t.string     :ip_address
      t.string     :user_agent
      t.jsonb      :metadata,   null: false, default: {}
      t.datetime   :created_at, null: false
    end

    add_index :audit_events, :action
    add_index :audit_events, :created_at
  end
end
