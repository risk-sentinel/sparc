class CreateTprControls < ActiveRecord::Migration[8.0]
  def change
    create_table :tpr_controls do |t|
      t.string :control_id
      t.string :title
      t.references :tpr_document, null: false, foreign_key: true

      t.timestamps
    end
  end
end
