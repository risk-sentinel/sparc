# frozen_string_literal: true

# #1147, #1151 — does this database actually match the schema the code expects?
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# The #1124 squash replaced 42 schema migrations with a version stamp. That is
# correct for `db:schema:load`, which builds a fresh database FROM `schema.rb`,
# and wrong for `db:migrate`, which never reads `schema.rb` at all. An upgraded
# deployment therefore ends with **zero pending migrations and a schema missing
# columns** — and the only signal was a 500 at runtime, on whichever page
# happened to touch a missing column first.
#
# "No pending migrations" answers the wrong question. This answers the right
# one: does every table, column, index, foreign key and extension the code
# expects exist, with the definition the code expects?
#
# ── How ────────────────────────────────────────────────────────────────────
#
# `schema.rb` is the authority, because it is what a fresh install gets and
# therefore what the code is written against. `SchemaDefinition` reads it into
# data by recording its DSL — never by executing it against a database, which is
# exactly the destructive operation this must never perform.
#
# `bin/schema_drift_sql` prints the presence check as plain SQL, for a
# deployment that cannot run this code yet. It reads the same `SchemaDefinition`.
#
# ── Two severities, because the boot gate REFUSES TO START on one of them ──
#
# #1151 puts this check in front of the web server: a container that does not
# match its schema does not bind its port. A false positive there is an outage
# the check caused, so the kinds are split by how reliably they can be measured:
#
#   STRUCTURAL — something is absent, or a column holds a different TYPE. Read
#     straight off the catalog, with nothing to normalise. The boot gate fails.
#   DEFINITIONAL — nullability, a default, an index's shape. Real drift, but
#     compared through type casting and dumper conventions that are easier to
#     get subtly wrong. Reported as a warning at boot; FATAL under `strict:`,
#     which is what the upgrade-path CI job and the specs run.
#
# The guard on both is one spec: the test database is built BY `schema:load`,
# so it must be strict-clean across every table. Any normalisation this file
# gets wrong fails there, on all 98 tables at once, before it can fail a boot.
#
# READ-ONLY BY CONSTRUCTION. It reports; `SchemaReconciliationService` is the
# only thing that acts on what it reports, and only additively.
class SchemaDriftService
  Drift = Struct.new(:kind, :table, :name, :expected, :actual, keyword_init: true) do
    def to_s
      case kind
      when :extension then "missing extension #{name}"
      when :table then "missing table #{table}"
      when :column then "missing column #{table}.#{name}"
      when :column_type then "column #{table}.#{name} is #{actual}, schema.rb declares #{expected}"
      when :nullability then "column #{table}.#{name} is #{actual ? 'NULL' : 'NOT NULL'}, schema.rb declares #{expected ? 'NULL' : 'NOT NULL'}"
      when :default then "column #{table}.#{name} defaults to #{actual.inspect}, schema.rb declares #{expected.inspect}"
      when :index then "missing index #{name} on #{table}"
      when :index_definition then "index #{name} on #{table} is #{actual}, schema.rb declares #{expected}"
      when :foreign_key then "missing foreign key #{table}.#{name} -> #{expected}"
      else raise ArgumentError, "unhandled drift kind #{kind.inspect}"
      end
    end

    def structural? = STRUCTURAL_KINDS.include?(kind)

    # Additive repair exists for it: create what is absent. Nothing that would
    # need a DROP, a retype or a data rewrite is ever reconcilable.
    def reconcilable? = RECONCILABLE_KINDS.include?(kind)
  end

  STRUCTURAL_KINDS = %i[extension table column column_type index foreign_key].freeze
  DEFINITIONAL_KINDS = %i[nullability default index_definition].freeze
  RECONCILABLE_KINDS = %i[extension table column index foreign_key].freeze

  # Retained for callers that referenced it before #1151; the recorder owns it.
  IGNORED_TABLES = SchemaDefinition::IGNORED_TABLES

  # `definition:` lets a long-lived caller (the health probe) pass a
  # SchemaDefinition it has already read, instead of re-reading schema.rb.
  def initialize(schema_path: Rails.root.join("db/schema.rb"), connection: ActiveRecord::Base.connection,
                 definition: nil)
    @schema_path = schema_path
    @connection = connection
    @definition = definition
  end

  def definition = @definition ||= SchemaDefinition.load(schema_path)

  # [Drift, ...] — empty when the database matches. Structural only unless
  # `strict:`; see the header for why the boot gate does not run strict.
  def drift(strict: false)
    strict ? all_drift : all_drift.select(&:structural?)
  end

  # Definitional drift a non-strict check does not fail on, so a caller can
  # still print it rather than hide it.
  def warnings = all_drift.reject(&:structural?)

  def clean?(strict: false) = drift(strict: strict).empty?

  # A report an operator can act on, grouped so a 40-column gap reads as one
  # upgrade problem rather than forty unrelated ones.
  def report(strict: false)
    failing = drift(strict: strict)
    advisory = strict ? [] : warnings
    checked = "#{definition.tables.size} table(s) checked#{' (strict)' if strict}"
    if failing.empty?
      return "schema matches db/schema.rb — #{checked}" if advisory.empty?

      return [ "schema matches db/schema.rb structurally — #{checked}",
               "WARNING: #{advisory.size} definitional difference(s), not fatal outside strict mode:",
               *grouped(advisory) ].join("\n")
    end

    lines = [ "SCHEMA DRIFT: #{failing.size} difference(s) against db/schema.rb — #{checked}", *grouped(failing) ]
    lines += [ "WARNING: #{advisory.size} definitional difference(s) as well:", *grouped(advisory) ] if advisory.any?
    lines << ""
    lines << "This database is BEHIND the schema the code expects. `db:migrate` reports"
    lines << "nothing pending because it only runs migrations it can see: one that was"
    lines << "archived by a squash is never run, and `schema.rb` is only read by a fresh"
    lines << "`db:schema:load`. `bin/rails db:reconcile_schema` repairs what is additive."
    lines.join("\n")
  end

  private

  attr_reader :schema_path, :connection

  def grouped(items)
    items.group_by(&:table).sort.flat_map do |table, found|
      [ "  #{table}:", *found.map { |i| "    - #{i}" } ]
    end
  end

  def all_drift
    @all_drift ||= missing_extensions + definition.tables.values.flat_map { |t| table_drift(t) } + missing_foreign_keys
  end

  def live_tables = @live_tables ||= connection.tables

  def missing_extensions
    live = connection.extensions.map { |e| SchemaDefinition.extension_name(e) }
    (definition.extensions - live).map { |e| Drift.new(kind: :extension, table: "(database)", name: e) }
  end

  def table_drift(table)
    return [ Drift.new(kind: :table, table: table.name) ] unless live_tables.include?(table.name)

    column_drift(table) + index_drift(table)
  end

  def column_drift(table)
    live = connection.columns(table.name).index_by(&:name)
    table.columns.flat_map do |expected|
      actual = live[expected.name]
      next [ Drift.new(kind: :column, table: table.name, name: expected.name) ] unless actual

      compare_column(table.name, expected, actual)
    end
  end

  def compare_column(table, expected, actual)
    want = type_signature(expected.type, expected.array?)
    have = type_signature(live_type(actual), actual.array?)
    return [ Drift.new(kind: :column_type, table: table, name: expected.name, expected: want, actual: have) ] if want != have

    found = []
    if expected.null? != actual.null
      found << Drift.new(kind: :nullability, table: table, name: expected.name, expected: expected.null?, actual: actual.null)
    end
    want_default = expected_default(expected, actual)
    have_default = live_default(actual)
    if want_default != have_default
      found << Drift.new(kind: :default, table: table, name: expected.name, expected: want_default, actual: have_default)
    end
    found
  end

  # The dumper writes `t.bigint`; the adapter reports a bigint as type
  # :integer with limit 8. Normalise the LIVE side to the dumper's vocabulary.
  def live_type(column)
    return :bigint if column.type == :integer && column.limit == 8

    column.type
  end

  def type_signature(type, array) = array ? "#{type}[]" : type.to_s

  def expected_default(expected, actual)
    return nil unless expected.default?
    return expected.default if expected.default.is_a?(SchemaDefinition::Expression)

    cast_type(actual).cast(expected.default)
  end

  def live_default(column)
    return SchemaDefinition::Expression.new(column.default_function) if column.default_function
    return nil if column.default.nil?

    cast_type(column).deserialize(column.default)
  end

  # The type ActiveRecord itself casts this column's values through, so a
  # schema.rb literal and a catalog default string are compared as the same
  # Ruby value (`false` vs `"false"`, `[]` vs `"{}"`).
  def cast_type(column) = column.fetch_cast_type(connection)

  def index_drift(table)
    live = connection.indexes(table.name).index_by(&:name)
    table.indexes.flat_map do |expected|
      actual = live[expected.name]
      next [ Drift.new(kind: :index, table: table.name, name: expected.name) ] unless actual

      want = index_shape(expected.columns, expected.options)
      have = index_shape(actual.columns, unique: actual.unique, where: actual.where, using: actual.using,
                                         opclass: actual.opclasses)
      next [] if want == have

      [ Drift.new(kind: :index_definition, table: table.name, name: expected.name,
                  expected: describe_shape(want), actual: describe_shape(have)) ]
    end
  end

  # Only the properties that change what the index enforces or can serve.
  # Defaults are filled in so an omitted option and its default compare equal:
  # the dumper omits `using: :btree` and `unique: false`.
  def index_shape(columns, options)
    columns = Array(columns).map(&:to_s)
    opclass = options[:opclass]
    opclass = columns.to_h { |c| [ c, opclass ] } if opclass.is_a?(Symbol) || opclass.is_a?(String)
    {
      columns: columns,
      unique: options[:unique] ? true : false,
      where: options[:where].presence,
      using: (options[:using] || :btree).to_sym,
      opclass: (opclass || {}).to_h { |k, v| [ k.to_s, v.to_s ] }.reject { |_, v| v.empty? }
    }
  end

  def describe_shape(shape)
    parts = [ "(#{shape[:columns].join(', ')})", shape[:using].to_s ]
    parts << "UNIQUE" if shape[:unique]
    parts << "WHERE #{shape[:where]}" if shape[:where]
    parts << "opclass #{shape[:opclass]}" if shape[:opclass].any?
    parts.join(" ")
  end

  # A foreign key is reported even when its table is missing too: the
  # reconciliation needs the full list to recreate one, and a report that
  # hid it would understate what a repair has to do.
  def missing_foreign_keys
    definition.foreign_keys.filter_map do |fk|
      column = foreign_key_column(fk)
      next if live_tables.include?(fk.from_table) &&
              connection.foreign_keys(fk.from_table).any? { |live| live.to_table == fk.to_table && live.column == column }

      Drift.new(kind: :foreign_key, table: fk.from_table, name: column, expected: fk.to_table)
    end
  end

  def foreign_key_column(fk) = (fk.options[:column] || "#{fk.to_table.singularize}_id").to_s
end
