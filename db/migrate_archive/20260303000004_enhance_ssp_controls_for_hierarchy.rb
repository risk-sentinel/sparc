class EnhanceSspControlsForHierarchy < ActiveRecord::Migration[8.1]
  def up
    # Paragraph/ReqID is null for provider statement rows
    change_column_null :ssp_controls, :control_id, true

    # Self-referential FK: provider statements point to their parent control
    add_column :ssp_controls, :parent_id, :bigint
    add_column :ssp_controls, :row_order, :integer, default: 0, null: false

    add_index :ssp_controls, :parent_id
    add_index :ssp_controls, [ :ssp_document_id, :row_order ]
    add_foreign_key :ssp_controls, :ssp_controls, column: :parent_id
  end

  def down
    remove_foreign_key :ssp_controls, column: :parent_id
    remove_index :ssp_controls, :parent_id
    remove_index :ssp_controls, [ :ssp_document_id, :row_order ]
    remove_column :ssp_controls, :row_order
    remove_column :ssp_controls, :parent_id
    change_column_null :ssp_controls, :control_id, false
  end
end
