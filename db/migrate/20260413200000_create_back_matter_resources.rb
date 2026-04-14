class CreateBackMatterResources < ActiveRecord::Migration[8.0]
  def change
    create_table :back_matter_resources do |t|
      t.string  :uuid,              null: false, default: -> { "gen_random_uuid()" }
      t.string  :resourceable_type, null: false
      t.bigint  :resourceable_id,   null: false
      t.references :evidence,       null: true, foreign_key: { on_delete: :nullify }
      t.string  :title,             null: false
      t.text    :description
      t.string  :media_type
      t.string  :href
      t.string  :source,            null: false, default: "managed"
      t.jsonb   :resource_data,     null: false, default: {}

      t.timestamps
    end

    add_index :back_matter_resources, :uuid, unique: true
    add_index :back_matter_resources, [ :resourceable_type, :resourceable_id ],
              name: "idx_back_matter_resources_on_resourceable"
  end
end
