class CreateSspControls < ActiveRecord::Migration[7.0]
  def change
    create_table :ssp_controls do |t|
      t.references :ssp_document, null: false, foreign_key: true
      t.string :control_id, null: false
      t.string :title

      t.timestamps
    end

    add_index :ssp_controls, [ :ssp_document_id, :control_id ], unique: true
  end
end
