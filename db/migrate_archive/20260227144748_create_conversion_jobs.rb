class CreateConversionJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :conversion_jobs do |t|
      t.string :job_type
      t.string :status
      t.integer :document_id
      t.string :document_type
      t.text :error_message

      t.timestamps
    end
  end
end
