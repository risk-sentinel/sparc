class AddCascadeDeleteToTprForeignKeys < ActiveRecord::Migration[8.1]
  def up
    # Remove existing foreign keys
    remove_foreign_key :tpr_control_fields, :tpr_controls
    remove_foreign_key :tpr_controls, :tpr_documents

    # Re-add with ON DELETE CASCADE for fast bulk deletion
    add_foreign_key :tpr_control_fields, :tpr_controls, on_delete: :cascade
    add_foreign_key :tpr_controls, :tpr_documents, on_delete: :cascade
  end

  def down
    remove_foreign_key :tpr_control_fields, :tpr_controls
    remove_foreign_key :tpr_controls, :tpr_documents

    add_foreign_key :tpr_control_fields, :tpr_controls
    add_foreign_key :tpr_controls, :tpr_documents
  end
end
