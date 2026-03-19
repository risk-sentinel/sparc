class CreateTprControlFields < ActiveRecord::Migration[8.0]
  def change
    create_table :tpr_control_fields do |t|
      t.references :tpr_control, null: false, foreign_key: true
      t.string :field_name
      t.text :field_value
      t.boolean :editable

      t.timestamps
    end
  end
end
