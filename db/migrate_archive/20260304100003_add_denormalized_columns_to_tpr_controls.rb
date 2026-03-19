class AddDenormalizedColumnsToTprControls < ActiveRecord::Migration[8.1]
  def change
    add_column :tpr_controls, :control_family, :string
    add_column :tpr_controls, :cached_result, :string
    add_index  :tpr_controls, [ :tpr_document_id, :control_family ]
    add_index  :tpr_controls, [ :tpr_document_id, :cached_result ]
  end
end
