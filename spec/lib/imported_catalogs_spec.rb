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
end
