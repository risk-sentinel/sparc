# frozen_string_literal: true

require "rails_helper"

# spec/support/imported_catalogs.rb hands a spec the rows of an earlier import
# instead of importing again. That is only sound if the rows put back are the
# rows the importer wrote, so this compares the two, table by table.
RSpec.describe ImportedCatalogs, :imports_this_run do
  let(:name) { "NIST_SP-800-53_rev5_catalog.json" }
  let(:connection) { ActiveRecord::Base.connection }
  let(:tables) { connection.tables.select { |t| connection.primary_key(t) == "id" }.sort }

  def max_ids
    tables.to_h { |t| [ t, connection.select_value("SELECT COALESCE(MAX(id), 0) FROM #{connection.quote_table_name(t)}").to_i ] }
  end

  def rows_since(before)
    tables.to_h do |t|
      [ t, connection.select_rows("SELECT * FROM #{connection.quote_table_name(t)} WHERE id > #{before.fetch(t)} ORDER BY id") ]
    end.reject { |_, rows| rows.empty? }
  end

  # Runs the block, returns what it wrote, and undoes it.
  def written
    before = max_ids
    rows = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      yield
      rows = rows_since(before)
      raise ActiveRecord::Rollback
    end
    rows
  end

  it "puts back exactly the rows the importer wrote" do
    described_class.snapshots.delete([ name, [] ])
    expect(ControlCatalog.count).to eq(0)

    imported = written { imported_catalog(name) }
    expect { @restored = written { imported_catalog(name) } }
      .to change { described_class.stats[:restored] }.by(1)

    expect(imported.keys).to include("control_catalogs", "control_families", "catalog_controls", "catalog_control_parts")
    expect(@restored.keys).to eq(imported.keys)
    imported.each { |table, rows| expect(@restored.fetch(table)).to eq(rows), "#{table} differs" }
  end

  it "returns the catalog the importer would" do
    catalog = imported_catalog(name)
    expect(catalog).to eq(ControlCatalog.sole)
    expect(catalog.control_families.count).to eq(20)
  end

  it "imports for real when the database already holds another catalog" do
    create(:control_catalog)
    expect { imported_catalog(name) }.to change { described_class.stats[:imported] }.by(1)
  end

  # #1264 — the CI cache file is JSON: it reads back as plain data, never as an
  # object of some class, and every snapshot comes back as it was kept.
  describe "the cache file" do
    around do |example|
      Dir.mktmpdir("imported-catalogs-") do |dir|
        original = ENV["IMPORTED_CATALOGS_CACHE"]
        ENV["IMPORTED_CATALOGS_CACHE"] = dir
        example.run
      ensure
        ENV["IMPORTED_CATALOGS_CACHE"] = original
      end
    end

    let(:file) { Pathname(ENV.fetch("IMPORTED_CATALOGS_CACHE")).join(ImportedCatalogs::CACHE_FILE) }

    # The snapshots a NEW run would read from the file; this run's stay as they were.
    def reloaded
      kept = described_class.instance_variable_get(:@snapshots)
      described_class.instance_variable_set(:@snapshots, nil)
      described_class.snapshots
    ensure
      described_class.instance_variable_set(:@snapshots, kept)
    end

    def as_utf8(tables)
      tables.transform_values { |rows| rows.map { |row| row.dup.force_encoding(Encoding::UTF_8) } }
    end

    it "is gzipped JSON, and reads back every snapshot as it was kept" do
      imported_catalog(name)
      described_class.instance_variable_set(:@unsaved, true)
      described_class.save_cache

      expect(JSON.parse(Zlib.gunzip(file.binread))).to all(include("key", "snapshot"))
      kept = described_class.snapshots
      back = reloaded

      expect(back.keys).to match_array(kept.keys)
      kept.each do |key, snapshot|
        expect(back.fetch(key)).to have_attributes(catalog_id: snapshot.catalog_id, counts: snapshot.counts,
                                                   max_ids: snapshot.max_ids, from_cache: true)
        expect(back.fetch(key).tables).to eq(as_utf8(snapshot.tables))
      end
    end

    it "ignores a file it cannot read, so the importer runs" do
      file.dirname.mkpath
      file.binwrite("not a cache file")

      expect { expect(reloaded).to eq({}) }.to output(/ImportedCatalogs: ignoring/).to_stderr
    end

    it "writes nothing when a captured row is not valid UTF-8" do
      kept = described_class.instance_variable_get(:@snapshots)
      bad = ImportedCatalogs::Snapshot.new(catalog_id: 1, counts: {}, max_ids: {}, tables: { "t" => [ "\xFF".b ] },
                                           from_cache: false)
      described_class.instance_variable_set(:@snapshots, { [ "bad.json", [] ] => bad })
      described_class.instance_variable_set(:@unsaved, true)

      expect { described_class.save_cache }.to output(/not valid UTF-8/).to_stderr
      expect(file).not_to exist
    ensure
      described_class.instance_variable_set(:@snapshots, kept)
    end
  end
end
