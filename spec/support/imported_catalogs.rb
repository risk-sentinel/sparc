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
# A copy is only kept from an import into a database whose catalogs are all
# kept copies themselves (or that has none), and never from an import that
# merged into a catalog already there: such an import mostly UPDATES rows, and
# only the rows an import adds are kept.
#
# Specs of the importer itself tag their group `:imports_this_run`. They may
# read a copy, but only one made by an import in this same run, never one read
# from the CI cache: on a cache hit the importer would otherwise not run in the
# very specs that test it. Examples about importing as such (a re-import, a
# database that already holds the catalog) call CatalogImportService directly.
module ImportedCatalogs
  Snapshot = Struct.new(:catalog_id, :counts, :max_ids, :tables, :from_cache, keyword_init: true)
  CACHE_FILE = "imported_catalogs.v2.json.gz"

  FIXTURES = Rails.root.join("spec/fixtures/files/catalogs")

  class << self
    def snapshots = (@snapshots ||= load_cache)

    # Counts for the summary line and for specs of this module.
    def stats = (@stats ||= Hash.new(0))

    # `this_run: true` refuses a copy read from the cache file.
    def fetch(name, this_run: false)
      connection = ActiveRecord::Base.connection
      present = present_catalogs(connection)
      key = [ name, present ]
      snapshot = snapshots[key]
      snapshot = nil if this_run && snapshot&.from_cache

      if snapshot && restore(connection, snapshot)
        stats[:restored] += 1
        return snapshot.counts.merge(catalog: ControlCatalog.find(snapshot.catalog_id))
      end

      before = max_ids(connection)
      result = CatalogImportService.call(File.open(FIXTURES.join(name)), name)
      stats[:imported] += 1
      if snapshot.nil? && keepable?(present, result)
        after = max_ids(connection)
        snapshots[key] = Snapshot.new(catalog_id: result.fetch(:catalog).id, counts: result.except(:catalog),
                                      max_ids: after, tables: capture(connection, before, after), from_cache: false)
        @unsaved = true
      end
      result
    end

    # One line after the run, so a run that quietly fell back to importing
    # every time (restores failing, or nothing ever reusable) can be seen.
    def summary
      return if stats.empty?

      "ImportedCatalogs: #{stats[:imported]} imported, #{stats[:restored]} put back, " \
        "#{stats[:restore_failed]} could not be put back"
    end

    # Writes the kept rows for the next run, when a cache directory is set and
    # this run kept something the file does not have.
    #
    # JSON, not Marshal: reading the file back can only produce hashes, arrays,
    # strings and numbers, never an object of some class (#1264). The snapshot
    # keys are arrays, which JSON cannot use as object keys, so the file is a
    # list of { key, snapshot } pairs. COPY rows go in as UTF-8; if one is not
    # valid UTF-8 nothing is written, and the next run imports for real.
    def save_cache
      return unless cache_path && @unsaved

      entries = snapshots.map do |key, snapshot|
        tables = snapshot.tables.transform_values { |rows| rows.map { |row| row.dup.force_encoding(Encoding::UTF_8) } }
        { "key" => key, "snapshot" => snapshot.to_h.except(:from_cache).merge(tables: tables) }
      end
      unless entries.all? { |entry| entry["snapshot"][:tables].values.flatten.all?(&:valid_encoding?) }
        warn "ImportedCatalogs: not writing #{cache_path}: a captured row is not valid UTF-8"
        return
      end

      FileUtils.mkdir_p(cache_path.dirname)
      File.binwrite("#{cache_path}.tmp", Zlib.gzip(JSON.generate(entries), level: Zlib::BEST_SPEED))
      File.rename("#{cache_path}.tmp", cache_path)
      @unsaved = false
    end

    private

    # See the header: only an import that added a new catalog beside kept ones.
    def keepable?(present, result)
      kept_ids = snapshots.each_value.map(&:catalog_id)
      present.none? { |id, _| id.to_i == result.fetch(:catalog).id } &&
        present.all? { |id, _| kept_ids.include?(id.to_i) }
    end

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
      entries = JSON.parse(Zlib.gunzip(File.binread(cache_path)))
      loaded = entries.to_h do |entry|
        saved = entry.fetch("snapshot")
        [ entry.fetch("key"), Snapshot.new(catalog_id: saved.fetch("catalog_id"),
                                           counts: saved.fetch("counts").transform_keys(&:to_sym),
                                           max_ids: saved.fetch("max_ids"), tables: saved.fetch("tables"),
                                           from_cache: true) ]
      end
      loaded.each_value do |snapshot|
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
    ImportedCatalogs.fetch(name, this_run: RSpec.current_example&.metadata&.fetch(:imports_this_run, false) || false)
  end
end

RSpec.configure do |config|
  config.include ImportedCatalogs
  config.after(:suite) do
    ImportedCatalogs.save_cache
    ImportedCatalogs.summary&.then { |line| config.reporter.message(line) }
  end
end
