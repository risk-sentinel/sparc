# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tempfile"

# #1151 — `bin/schema_drift_sql` was blind to a missing TABLE.
#
# The emitted query inner-joined `information_schema.tables`, so a table that
# does not exist contributed no rows and the check reported CLEAN. That is the
# likeliest damage in exactly the old-database case the script exists for: a
# deployment on v1.15.3 upgrading straight to v1.16.3 is missing four
# table-creating migrations, and the script said nothing about any of them.
#
# These examples run the generator and EXECUTE its SQL against the test
# database. No DDL is performed — instead the generator is pointed at a fixture
# schema that declares structure the database does not have, which exercises the
# same query without dropping anything out from under the suite.
RSpec.describe "bin/schema_drift_sql" do
  def generate(schema_path = nil)
    cmd = [ Rails.root.join("bin/schema_drift_sql").to_s ]
    cmd << schema_path.to_s if schema_path
    out, err, status = Open3.capture3(*cmd)
    [ out, err, status ]
  end

  def run_check(sql)
    ActiveRecord::Base.connection.select_all(sql).to_a
  end

  def fixture_schema(body)
    file = Tempfile.new([ "schema", ".rb" ])
    file.write(<<~RUBY)
      ActiveRecord::Schema[8.1].define(version: 2026_09_19_000000) do
      #{body}
      end
    RUBY
    file.flush
    file
  end

  describe "against the real schema.rb and the test database" do
    # The test database is built by schema:load, so it matches by construction.
    # Asserting it is not ceremony: if this reported drift, every other example
    # here would be meaningless.
    it "reports no drift" do
      sql, err, status = generate
      expect(status).to be_success, err
      expect(run_check(sql)).to be_empty
    end

    it "checks a real number of tables — a parser that found nothing would also report clean" do
      sql, = generate
      expect(sql).to match(/-- Expected schema from .*: (\d+) tables, (\d+) columns\./)
      tables = sql[/(\d+) tables/, 1].to_i
      columns = sql[/(\d+) columns/, 1].to_i
      expect(tables).to be > 50
      expect(columns).to be > 500
    end
  end

  describe "a missing TABLE" do
    # The regression this issue exists for. Before the fix the inner join
    # dropped the row entirely and this returned [].
    it "is reported, and named" do
      file = fixture_schema(<<~RUBY)
        create_table "definitely_not_a_real_table", force: :cascade do |t|
          t.string "name"
          t.datetime "created_at", null: false
        end
      RUBY

      sql, err, status = generate(file.path)
      expect(status).to be_success, err

      rows = run_check(sql)
      expect(rows.map { |r| r["table_name"] }).to include("definitely_not_a_real_table")
      expect(rows.find { |r| r["table_name"] == "definitely_not_a_real_table" }["kind"])
        .to eq("missing table")
    ensure
      file&.close!
    end

    it "is listed ONCE, not once per column it would have had" do
      file = fixture_schema(<<~RUBY)
        create_table "definitely_not_a_real_table", force: :cascade do |t|
          t.string "alpha"
          t.string "bravo"
          t.string "charlie"
          t.string "delta"
        end
      RUBY

      sql, = generate(file.path)
      rows = run_check(sql).select { |r| r["table_name"] == "definitely_not_a_real_table" }

      expect(rows.size).to eq(1)
      expect(rows.first["column_name"]).to be_nil
    ensure
      file&.close!
    end
  end

  describe "a missing COLUMN on a table that exists" do
    it "is still reported, with the column named" do
      file = fixture_schema(<<~RUBY)
        create_table "users", force: :cascade do |t|
          t.string "definitely_not_a_real_column"
        end
      RUBY

      sql, = generate(file.path)
      rows = run_check(sql)

      row = rows.find { |r| r["column_name"] == "definitely_not_a_real_column" }
      expect(row).not_to be_nil
      expect(row["kind"]).to eq("missing column")
      expect(row["table_name"]).to eq("users")
    ensure
      file&.close!
    end

    it "is NOT reported for a table that is itself missing — that would be noise" do
      file = fixture_schema(<<~RUBY)
        create_table "definitely_not_a_real_table", force: :cascade do |t|
          t.string "alpha"
        end
      RUBY

      sql, = generate(file.path)
      rows = run_check(sql)

      expect(rows.map { |r| r["kind"] }).not_to include("missing column")
    ensure
      file&.close!
    end
  end

  describe "refusing to emit a check that would pass on anything" do
    it "aborts when the schema parses to no columns" do
      file = Tempfile.new([ "empty_schema", ".rb" ])
      file.write("ActiveRecord::Schema[8.1].define(version: 1) do\nend\n")
      file.flush

      _out, err, status = generate(file.path)

      expect(status).not_to be_success
      expect(err).to match(/parsed no columns/)
    ensure
      file&.close!
    end

    it "aborts when the schema file does not exist" do
      _out, err, status = generate("/nonexistent/schema.rb")

      expect(status).not_to be_success
      expect(err).to match(/no schema at/)
    end
  end
end
