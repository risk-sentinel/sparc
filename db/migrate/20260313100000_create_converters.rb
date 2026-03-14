class CreateConverters < ActiveRecord::Migration[8.1]
  def change
    create_table :converters do |t|
      t.string  :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string  :name, null: false
      t.text    :description
      t.string  :converter_type, null: false
      t.string  :version, default: "1.0"
      t.string  :status, null: false, default: "draft"
      t.string  :source_framework
      t.string  :target_framework, default: "NIST SP 800-53"
      t.jsonb   :metadata_extra, default: {}
      t.timestamps
    end

    add_index :converters, :uuid, unique: true
    add_index :converters, :converter_type
    add_index :converters, :status
  end
end
