# frozen_string_literal: true

require "rails_helper"

# #1151 — the recorder every schema check and the reconciliation read from.
#
# The test database is built by `schema:load` from the same file, so the live
# catalog is the answer key: what the recorder read must be exactly what Rails
# built. A recorder that missed a table, a column or an index would make every
# check built on it blind to that object — and report it clean.
RSpec.describe SchemaDefinition do
  subject(:definition) { described_class.load(Rails.root.join("db/schema.rb")) }

  let(:connection) { ActiveRecord::Base.connection }
  let(:live_tables) { connection.tables - described_class::IGNORED_TABLES }

  it "reads the version the dump declares" do
    expect(definition.version).to eq(ActiveRecord::Base.connection_pool.migration_context.current_version)
  end

  it "records exactly the tables the database holds" do
    expect(definition.table_names).to match_array(live_tables)
  end

  it "records every column of every table (bar the implicit primary key)" do
    live = live_tables.to_h { |t| [ t, connection.columns(t).map(&:name) - [ "id" ] ] }
    read = definition.tables.transform_values { |t| t.columns.map(&:name) }

    expect(read.transform_values(&:sort)).to eq(live.transform_values(&:sort))
  end

  it "records every index of every table" do
    live = live_tables.to_h { |t| [ t, connection.indexes(t).map(&:name).sort ] }

    expect(definition.tables.transform_values { |t| t.indexes.map(&:name).sort }).to eq(live)
  end

  it "records every foreign key" do
    live = live_tables.sum { |t| connection.foreign_keys(t).size }

    expect(definition.foreign_keys.size).to eq(live)
  end

  it "records extensions without their schema qualifier" do
    expect(definition.extensions).to include("pg_trgm", "plpgsql")
  end

  it "keeps a lambda default as SQL, distinct from a string literal" do
    uuid = definition.tables["authorization_boundaries"].column("uuid")
    status = definition.tables["authorization_boundaries"].column("status")

    expect(uuid.default).to eq(described_class::Expression.new("gen_random_uuid()"))
    expect(status.default).to eq("draft")
    expect(uuid).not_to be_null
  end

  describe "refusing rather than guessing" do
    def parse(body) = described_class.new(<<~RUBY)
      ActiveRecord::Schema[8.1].define(version: 1) do
      #{body}
      end
    RUBY

    it "raises on a column type it does not know" do
      expect { parse(%(create_table "x" do |t|\n t.geometry "shape"\nend)) }
        .to raise_error(NoMethodError, /x\.shape|geometry/)
    end

    # PR #1188 review: types the drift comparison cannot read correctly are
    # refused where schema.rb is first read (development, CI), never at a
    # production boot.
    %w[serial bigserial virtual].each do |type|
      it "refuses a #{type} column until the comparison supports it" do
        expect { parse(%(create_table "x" do |t|\n t.#{type} "c"\nend)) }
          .to raise_error(ArgumentError, /x\.c as `#{type}`/)
      end
    end

    it "raises on a top-level statement it does not record" do
      expect { parse(%(create_table "x" do |t|\n t.string "a"\nend\ncreate_view "v", "SELECT 1")) }
        .to raise_error(NoMethodError, /create_view/)
    end

    it "raises on a file that is not a schema dump" do
      expect { described_class.new("puts 1\n") }.to raise_error(ArgumentError, /define/)
    end

    it "refuses a schema with no tables" do
      expect { parse("") }.to raise_error(ArgumentError, /declares no tables/)
    end

    it "never touches a database — reading is recording, not executing" do
      expect(ActiveRecord::Base).not_to receive(:connection)

      parse(%(create_table "x" do |t|\n t.string "a"\nend))
    end
  end
end
