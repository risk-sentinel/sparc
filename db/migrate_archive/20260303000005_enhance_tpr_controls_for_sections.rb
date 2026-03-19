class EnhanceTprControlsForSections < ActiveRecord::Migration[8.1]
  def change
    # Workbook tab name each row was imported from
    add_column :tpr_controls, :section, :string

    # Subject field parsed: "Asset/Component | Environment"
    add_column :tpr_controls, :subject_asset, :string
    add_column :tpr_controls, :subject_environment, :string

    # Preserve import row order globally across all tabs
    add_column :tpr_controls, :row_order, :integer, default: 0, null: false

    add_index :tpr_controls, :section
    add_index :tpr_controls, [ :tpr_document_id, :row_order ]
  end
end
