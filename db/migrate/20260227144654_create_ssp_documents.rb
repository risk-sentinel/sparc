class CreateSspDocuments < ActiveRecord::Migration[7.0]
  def change
    create_table :ssp_documents do |t|
      t.string :name, null: false
      t.string :file_type, null: false
      t.string :status, default: 'pending'
      t.string :original_filename
      t.text :error_message

      t.timestamps
    end

    add_index :ssp_documents, :status
    add_index :ssp_documents, :created_at
  end
end