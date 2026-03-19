class AddCompositeIndexToTprControlFields < ActiveRecord::Migration[8.1]
  def change
    add_index :tpr_control_fields, [ :tpr_control_id, :field_name ],
              name: "index_tpr_control_fields_on_control_id_and_field_name"
  end
end
