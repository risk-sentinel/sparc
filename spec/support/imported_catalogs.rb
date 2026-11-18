# frozen_string_literal: true

# Gives a spec a real NIST catalog without importing it again.
#
#   let!(:rev5) { imported_catalog("NIST_SP-800-53_rev5_catalog.json") }
#
# The full Rev 5 catalog takes CatalogImportService about fifteen seconds, and
# about a hundred examples each import it. The result is the same every time,
# so the first example to ask runs the real importer and this module keeps
# every row it wrote; later examples get those rows put back, which takes a
# fraction of a second.
#
# Nothing is shared between examples. The rows are inserted inside the asking
# example's own transaction and roll back with it, exactly as an import would.
# They are kept in memory for the life of the process, so a new run (or another
# CI shard) imports afresh from the fixture as it is on disk.
#
# Unless IMPORTED_CATALOGS_CACHE names a directory: then the kept rows are
# written there when the run ends and read back by the next one, which skips
# even the first import. Whoever sets it owns the question of when that copy is
# out of date. CI does (ci.yml), keying its cache on every file an import
# reads; nothing sets it for a developer's own runs.
#
# The importer still runs for real whenever a kept copy could differ from a
# fresh import:
#   - the catalogs already in the database are not the ones present when the
#     copy was taken (an import may merge into, or read, what is there);
#   - the rows cannot be put back as they were (their ids are taken).
#
# Specs of the importer itself should call CatalogImportService directly.
module ImportedCatalogs
  Snapshot = Struct.new(:catalog_id, :counts, :max_ids, :tables, keyword_init: true)
  CACHE_FILE = "imported_catalogs.v1.bin"

  FIXTURES = Rails.root.join("spec/fixtures/files/catalogs")

  class << self
    def snapshots = (@snapshots ||= load_cache)

    # Counts for the run summary and for specs of this module.
    def stats = (@stats ||= Hash.new(0))

    def fetch(name)
      connection = ActiveRecord::Base.connection
      key = [ name, present_catalogs(connection) ]

      if (snapshot = snapshots[key]) && restore(connection, snapshot)
        stats[:restored] += 1
        return snapshot.counts.merge(catalog: ControlCatalog.find(snapshot.catalog_id))
      end

      before = max_ids(connection)
      result = CatalogImportService.call(File.open(FIXTURES.join(name)), name)
      stats[:imported] += 1
      unless snapshots.key?(key)
        after = max_ids(connection)
        snapshots[key] = Snapshot.new(catalog_id: result.fetch(:catalog).id, counts: result.except(:catalog),
                                      max_ids: after, tables: capture(connection, before, after))
        @unsaved = true
      end
      result
    end

    # Writes the kept rows for the next run, when a cache directory is set and
    # this run kept something the file does not have.
    def save_cache
      return unless cache_path && @unsaved

      FileUtils.mkdir_p(cache_path.dirname)
      data = snapshots.transform_values(&:to_h)
      File.binwrite("#{cache_path}.tmp", Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_SPEED))
      File.rename("#{cache_path}.tmp", cache_path)
      @unsaved = false
    end

    private

    def cache_path
      dir = ENV["IMPORTED_CATALOGS_CACHE"].presence
      dir && Pathname(dir).expand_path.join(CACHE_FILE)
    end

    # The rows an earlier run kept, or nothing. Their ids were handed out by
    # that run's database, so this one's sequences are moved past them first:
    # no row made later can then take an id a kept row will need.
    def load_cache
      return {} unless cache_path&.file?

      connection = ActiveRecord::Base.connection
      loaded = Marshal.load(Zlib::Inflate.inflate(File.binread(cache_path))) # rubocop:disable Security/MarshalLoad -- a file this module wrote
      loaded.transform_values { |attributes| Snapshot.new(**attributes) }.each_value do |snapshot|
        snapshot.max_ids.each do |table, max|
          sequence = connection.select_value("SELECT pg_get_serial_sequence(#{connection.quote(table)}, 'id')") or next
          connection.execute("SELECT setval('#{sequence}', GREATEST(#{max.to_i}, (SELECT last_value FROM #{sequence})))")
        end
      end
    rescue StandardError => e
      warn "ImportedCatalogs: ignoring #{cache_path} (#{e.class}: #{e.message})"
      {}
    end

    # What an import could see or merge into: the catalogs already there.
    def present_catalogs(connection)
      connection.select_rows("SELECT id, name FROM control_catalogs ORDER BY id")
    end

    def tables(connection)
      @tables ||= connection.tables.select { |t| connection.primary_key(t) == "id" }.sort
    end

    def max_ids(connection)
      tables(connection).to_h do |table|
        [ table, connection.select_value("SELECT COALESCE(MAX(id), 0) FROM #{connection.quote_table_name(table)}").to_i ]
      end
    end

    # Every row written since `before`, per table, as Postgres COPY text.
    def capture(connection, before, after)
      raw = connection.raw_connection
      captured = after.select { |table, max| max > before.fetch(table) }.to_h do |table, _|
        rows = []
        sql = "COPY (SELECT * FROM #{connection.quote_table_name(table)} " \
              "WHERE id > #{before.fetch(table)} ORDER BY id) TO STDOUT"
        raw.copy_data(sql) do
          while (row = raw.get_copy_data)
            rows << row
          end
        end
        [ table, rows ]
      end
      insertion_order(connection, captured.keys).to_h { |table| [ table, captured.fetch(table) ] }
    end

    # Referenced tables first. A foreign key is checked at the end of each COPY,
    # so rows of one table may refer to each other in any order.
    def insertion_order(connection, names)
      needs = names.to_h do |table|
        [ table, connection.foreign_keys(table).map(&:to_table).uniq & (names - [ table ]) ]
      end
      ordered = []
      until needs.empty?
        ready = needs.select { |_, deps| (deps - ordered).empty? }.keys
        ready = [ needs.keys.first ] if ready.empty? # a cycle: restore will fail and the importer runs instead
        ordered.concat(ready)
        needs.except!(*ready)
      end
      ordered
    end

    # True when every row went back. A failure (an id already taken) undoes the
    # partial insert and leaves the example's transaction usable.
    def restore(connection, snapshot)
      ActiveRecord::Base.transaction(requires_new: true) do
        raw = connection.raw_connection # asked for inside the block, so the savepoint is open before COPY
        snapshot.tables.each do |table, rows|
          raw.copy_data("COPY #{connection.quote_table_name(table)} FROM STDIN") do
            rows.each { |row| raw.put_copy_data(row) }
          end
        end
      end
      true
    rescue ActiveRecord::StatementInvalid, PG::Error
      stats[:restore_failed] += 1
      false
    end
  end

  # The catalog imported from spec/fixtures/files/catalogs/<name>, as
  # CatalogImportService.call(file, name)[:catalog] returns it.
  def imported_catalog(name)
    imported_catalog_result(name).fetch(:catalog)
  end

  # The whole hash CatalogImportService.call(file, name) returns: the catalog
  # and the importer's counts (families, controls, created, updated).
  def imported_catalog_result(name)
    ImportedCatalogs.fetch(name)
  end
end

RSpec.configure do |config|
  config.include ImportedCatalogs
  config.after(:suite) { ImportedCatalogs.save_cache }
end
