class CreateSspControlFields < ActiveRecord::Migration[7.0]
  def change
    create_table :ssp_control_fields do |t|
      t.references :ssp_control, null: false, foreign_key: true
      t.string :field_name, null: false
      t.text :field_value
      t.boolean :editable, default: false

      t.timestamps
    end

    add_index :ssp_control_fields, [:ssp_control_id, :field_name]
  end
end