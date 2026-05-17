# Adds a stable `uuid` column to nested OSCAL entity tables that lack one.
# Pairs with #397: OSCAL exports stop calling SecureRandom.uuid for these
# entities and use record.uuid instead, so re-exports are UUID-stable.
#
# poam_items already has poam_item_uuid (string, optional) -- promote it
# to a first-class uuid column. Backfill preserves the existing string
# value when present so already-imported POAMs keep their identity.
#
# Idempotent: each step gated by column_exists? / index_exists?. Backfill
# uses a single SQL UPDATE per table (PostgreSQL gen_random_uuid() is
# server-side; ~200-400ms even on 100K rows) -- no per-row Ruby loop.
class AddUuidToOscalControlTables < ActiveRecord::Migration[8.1]
  TABLES = %i[
    sap_controls
    sar_controls
    ssp_controls
    cdef_controls
    profile_controls
    catalog_controls
  ].freeze

  def up
    TABLES.each { |t| add_uuid_column(t) }
    add_uuid_to_poam_items
  end

  def down
    TABLES.each do |t|
      remove_index t, :uuid if index_exists?(t, :uuid)
      remove_column t, :uuid if column_exists?(t, :uuid)
    end
    if column_exists?(:poam_items, :uuid)
      remove_index :poam_items, :uuid if index_exists?(:poam_items, :uuid)
      remove_column :poam_items, :uuid
    end
  end

  private

  def add_uuid_column(table)
    return if column_exists?(table, :uuid)

    add_column table, :uuid, :string, default: -> { "gen_random_uuid()" }
    say_with_time "Backfilling #{table}.uuid" do
      execute "UPDATE #{table} SET uuid = gen_random_uuid() WHERE uuid IS NULL"
    end
    change_column_null table, :uuid, false
    add_index table, :uuid, unique: true unless index_exists?(table, :uuid)
  end

  def add_uuid_to_poam_items
    return if column_exists?(:poam_items, :uuid)

    add_column :poam_items, :uuid, :string, default: -> { "gen_random_uuid()" }
    say_with_time "Backfilling poam_items.uuid from poam_item_uuid" do
      # Cast gen_random_uuid() (PG type `uuid`) to text so COALESCE matches
      # the type of poam_item_uuid (`text`).
      execute <<~SQL
        UPDATE poam_items
        SET uuid = COALESCE(NULLIF(poam_item_uuid, ''), gen_random_uuid()::text)
        WHERE uuid IS NULL
      SQL
    end
    change_column_null :poam_items, :uuid, false
    add_index :poam_items, :uuid, unique: true unless index_exists?(:poam_items, :uuid)
  end
end
