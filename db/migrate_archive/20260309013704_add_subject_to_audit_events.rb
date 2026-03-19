class AddSubjectToAuditEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_events, :subject_type, :string
    add_column :audit_events, :subject_id, :bigint

    add_index :audit_events, [ :subject_type, :subject_id ]
    add_index :audit_events, :subject_type
  end
end
