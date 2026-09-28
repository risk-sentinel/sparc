# frozen_string_literal: true

require "rails_helper"

# #1147 — the check that would have caught the squash gap before a deploy.
RSpec.describe SchemaDriftService do
  def connection = ActiveRecord::Base.connection

  after { [ AuthorizationBoundary, SspInformationType, CdefControl ].each(&:reset_column_information) }

  describe "a database that matches schema.rb" do
    # The test database is built by schema:load, so it is the matching case by
    # construction — which is exactly why it must be asserted: if this reported
    # drift on a clean database, every later example would be meaningless.
    it "reports none" do
      expect(described_class.new.drift).to be_empty
      expect(described_class.new).to be_clean
    end

    it "says how many tables it checked, rather than a bare 'ok'" do
      expect(described_class.new.report).to match(/schema matches db\/schema\.rb — \d+ table\(s\) checked/)
    end

    it "checks a real number of tables — a parser that found nothing would also report clean" do
      definition = described_class.new.definition
      expect(definition.tables.size).to be > 40
      expect(definition.tables["authorization_boundaries"].columns.map(&:name)).to include("security_objective_confidentiality")
    end

    # #1151 — the boot gate refuses to start on drift, so a false positive is
    # an outage. This database was built BY schema:load: every type, default,
    # nullability and index shape comparison must agree with it, on every table.
    it "is clean in STRICT mode too — the guard against false positives in the boot gate" do
      expect(described_class.new.drift(strict: true)).to eq([])
      expect(described_class.new.warnings).to eq([])
    end
  end

  # #1151 — past presence. Each kind is proven to FIRE, because a comparison
  # that could never differ would also report the clean database above.
  describe "a column that exists with the wrong definition" do
    it "reports a changed TYPE as structural — it fails the boot gate" do
      connection.change_column(:ssp_information_types, :title, :text)

      found = described_class.new.drift

      expect(found.map(&:to_s)).to include("column ssp_information_types.title is text, schema.rb declares string")
      expect(found.find { |d| d.kind == :column_type }).not_to be_reconcilable
    end

    it "tells a bigint from an integer, which the adapter reports as one type" do
      connection.change_column(:ssp_information_types, :authorization_boundary_id, :integer)

      expect(described_class.new.drift.map(&:to_s))
        .to include("column ssp_information_types.authorization_boundary_id is integer, schema.rb declares bigint")
    end

    it "reports nullability only in strict mode, and as a warning otherwise" do
      connection.change_column_null(:authorization_boundaries, :uuid, true)

      service = described_class.new
      expect(service.drift).to be_empty
      expect(service.warnings.map(&:to_s)).to include("column authorization_boundaries.uuid is NULL, schema.rb declares NOT NULL")
      expect(service.drift(strict: true).map(&:kind)).to include(:nullability)
    end

    it "compares a literal default as a value, not as the catalog's string" do
      connection.change_column_default(:authorization_boundaries, :status, "retired")

      found = described_class.new.drift(strict: true).find { |d| d.kind == :default }
      expect(found.to_s).to match(/authorization_boundaries\.status defaults to "retired"/)
    end

    # Nothing in today's schema.rb needs the cast — every default is already in
    # its final Ruby form — but the dumper writes a decimal default as the STRING
    # "0.0" while the catalog deserialises to a BigDecimal. Uncast, that is a
    # false positive, and at boot a false positive is a refusal to start.
    it "casts a schema literal through the column's type, so a decimal default is not a false positive" do
      connection.create_table(:drift_cast_probes) { |t| t.decimal :amount, precision: 10, scale: 2, default: "0.0" }
      schema = Tempfile.new([ "schema", ".rb" ])
      schema.write(<<~RUBY)
        ActiveRecord::Schema[8.1].define(version: 1) do
          create_table "drift_cast_probes", force: :cascade do |t|
            t.decimal "amount", precision: 10, scale: 2, default: "0.0"
          end
        end
      RUBY
      schema.flush

      expect(described_class.new(schema_path: schema.path).drift(strict: true)).to eq([])
    ensure
      schema&.close!
    end

    it "compares an expression default by its SQL" do
      connection.change_column_default(:authorization_boundaries, :uuid, nil)

      found = described_class.new.drift(strict: true).find { |d| d.kind == :default }
      expect(found.expected).to eq(SchemaDefinition::Expression.new("gen_random_uuid()"))
      expect(found.actual).to be_nil
    end

    it "reports an index whose shape changed under the same name" do
      connection.remove_index(:cdef_controls, name: "index_cdef_controls_on_document_and_source")
      connection.add_index(:cdef_controls, :cdef_document_id, name: "index_cdef_controls_on_document_and_source")

      found = described_class.new.drift(strict: true).find { |d| d.kind == :index_definition }
      expect(found&.name).to eq("index_cdef_controls_on_document_and_source")
    end
  end


  # PR #1188 review: check constraints on an EXISTING table were never compared.
  describe "check constraints" do
    def cc_schema
      file = Tempfile.new([ "schema", ".rb" ])
      file.write(<<~RUBY)
        ActiveRecord::Schema[8.1].define(version: 1) do
          create_table "cc_probes", force: :cascade do |t|
            t.integer "n"
            t.check_constraint "n > 0", name: "n_positive"
          end
        end
      RUBY
      file.flush
      file
    end

    it "names a check constraint missing from a table that exists — structural" do
      connection.create_table(:cc_probes) { |t| t.integer :n }
      schema = cc_schema

      found = described_class.new(schema_path: schema.path).drift

      expect(found.map(&:to_s)).to eq([ "missing check constraint n_positive on cc_probes" ])
      expect(found.first).to be_reconcilable
    ensure
      schema&.close!
    end

    it "reports nothing when the constraint is there" do
      connection.create_table(:cc_probes) { |t| t.integer :n; t.check_constraint "n > 0", name: "n_positive" }
      schema = cc_schema

      expect(described_class.new(schema_path: schema.path).drift(strict: true)).to eq([])
    ensure
      schema&.close!
    end
  end

  describe "foreign keys and extensions" do
    it "names a missing foreign key" do
      connection.remove_foreign_key(:api_tokens, :users)

      expect(described_class.new.drift.map(&:to_s)).to include("missing foreign key api_tokens.user_id -> users")
    end

    it "names a missing extension" do
      connection.execute("DROP EXTENSION pg_trgm CASCADE")

      expect(described_class.new.drift.map(&:to_s)).to include("missing extension pg_trgm")
    end
  end

  describe "a database behind schema.rb — the production case" do
    it "names each missing column" do
      connection.remove_column(:ssp_information_types, :authorization_boundary_id)
      SspInformationType.reset_column_information

      found = described_class.new.drift

      expect(found.map(&:to_s)).to include("missing column ssp_information_types.authorization_boundary_id")
      expect(described_class.new).not_to be_clean
    end

    it "finds drift on EVERY affected table, not just the first" do
      connection.remove_column(:ssp_information_types, :authorization_boundary_id)
      connection.remove_column(:authorization_boundaries, :security_objective_integrity)
      connection.remove_column(:cdef_controls, :component_uuid)

      tables = described_class.new.drift.map(&:table).uniq

      expect(tables).to include("ssp_information_types", "authorization_boundaries", "cdef_controls")
    end

    it "names a missing index" do
      connection.remove_index(:cdef_controls, name: "index_cdef_controls_on_document_and_source")

      expect(described_class.new.drift.map(&:to_s))
        .to include("missing index index_cdef_controls_on_document_and_source on cdef_controls")
    end

    it "names a missing table" do
      connection.drop_table(:ssp_information_types, force: :cascade)

      expect(described_class.new.drift.map(&:to_s)).to include("missing table ssp_information_types")
    end

    it "reports the upgrade explanation, not just a list" do
      connection.remove_column(:cdef_controls, :implementation_source)

      report = described_class.new.report

      expect(report).to include("SCHEMA DRIFT")
      expect(report).to include("cdef_controls:")
      expect(report).to match(/db:migrate. reports|archived/)
    end
  end

  describe "an unrecognised drift kind" do
    # The rendering `case` refuses rather than returning nil: a drift that
    # printed as an empty line would read as "nothing missing", which is the
    # failure mode this whole service exists to end.
    it "raises instead of rendering nothing" do
      expect { described_class::Drift.new(kind: :sequence, table: "x", name: "y").to_s }
        .to raise_error(ArgumentError, /unhandled drift kind/)
    end
  end

  describe "read-only by construction" do
    it "changes nothing about the database" do
      before_columns = connection.columns(:authorization_boundaries).map(&:name).sort

      described_class.new.report

      expect(connection.columns(:authorization_boundaries).map(&:name).sort).to eq(before_columns)
    end
  end
end
