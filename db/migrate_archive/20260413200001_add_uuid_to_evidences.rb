class AddUuidToEvidences < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:evidences, :uuid)
      add_column :evidences, :uuid, :string, default: -> { "gen_random_uuid()" }

      reversible do |dir|
        dir.up do
          # Backfill existing records with generated UUIDs
          execute "UPDATE evidences SET uuid = gen_random_uuid() WHERE uuid IS NULL"
        end
      end

      change_column_null :evidences, :uuid, false
      add_index :evidences, :uuid, unique: true
    end
  end
end
