class CreateSeedSections < ActiveRecord::Migration[8.1]
  def change
    create_table :seed_sections, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :version, default: "1.0.0"
      t.string :status, default: "pending"
      t.text :error_message
      t.integer :records_created, default: 0
      t.datetime :completed_at

      t.timestamps
    end

    unless index_exists?(:seed_sections, :name)
      add_index :seed_sections, :name, unique: true
    end
  end
end
