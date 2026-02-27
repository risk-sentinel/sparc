class CreateTprDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :tpr_documents do |t|
      t.string :name
      t.string :file_type
      t.string :status
      t.string :original_filename

      t.timestamps
    end
  end
end
