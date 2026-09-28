# frozen_string_literal: true

# #1151 — the full definition `db/schema.rb` declares, as data.
#
#   definition = SchemaDefinition.load("db/schema.rb")
#   definition.tables["cdef_controls"].columns.first  # => name, type, options
#
# ── Why a recorder, and not the line regex it replaces ────────────────────
#
# #1147's drift check parsed `schema.rb` line by line and kept NAMES only. That
# is enough to say a column is missing; it cannot say what to create in its
# place, and it cannot see a column that exists with the wrong type. #1151 needs
# both: the boot gate must know what "matches" means past presence, and the
# reconciliation must build a missing column with its real type, nullability
# and default.
#
# So the dump's own DSL is evaluated — but against THIS object, which records
# each call and does nothing else. No database connection exists here and
# nothing is executed against one: `create_table` appends to a hash. That keeps
# the property the regex was protecting (reading the schema can never change a
# database) while reading the schema the way Rails itself reads it.
#
# ── It EXECUTES the file — point it only at a schema.rb you trust ─────────
#
# Recording means evaluating: `instance_eval` runs whatever Ruby the file
# contains, with this process's privileges. The line regex it replaced was
# safe on any input; this is not (PR #1188 review). The app reads its own
# db/schema.rb, and bin/upgrade_path_check reads one out of a SPARC image it
# pulled by tag — never hand it a schema.rb from a source you do not trust.
#
# ── Plain Ruby, on purpose ─────────────────────────────────────────────────
#
# No Rails, no ActiveSupport. `bin/schema_drift_sql` requires this file from a
# checkout that may be pointed at a deployment several releases old, where
# nothing but Ruby can be assumed. Zeitwerk autoloads it as `::SchemaDefinition`
# inside the app, so there is one parser, not two that have to agree.
#
# ── Loud on anything unrecognised ──────────────────────────────────────────
#
# A method the recorder does not know raises. A parser that silently skipped an
# unfamiliar statement would report a schema smaller than the real one, and a
# drift check built on it would call a database clean because it never looked
# at part of it — the failure mode #1151 exists to end.
class SchemaDefinition
  Column = Struct.new(:name, :type, :options, keyword_init: true) do
    def null? = options.fetch(:null, true)
    def array? = options.fetch(:array, false)
    def default = options[:default]
    def default? = options.key?(:default)
  end

  Index = Struct.new(:table, :name, :columns, :options, keyword_init: true)

  Table = Struct.new(:name, :options, :columns, :indexes, :check_constraints, keyword_init: true) do
    def column(name) = columns.find { |c| c.name == name }
  end

  ForeignKey = Struct.new(:from_table, :to_table, :options, keyword_init: true)

  # A default written as `-> { "gen_random_uuid()" }` is SQL evaluated by the
  # database, not a literal value. Kept distinct so nothing ever compares or
  # writes it as the string it happens to be spelled with.
  Expression = Struct.new(:sql) do
    def to_proc = (sql = self.sql; -> { sql })
    def inspect = "-> { #{sql.inspect} }"
  end

  # Tables Rails maintains itself; `schema.rb` does not describe them.
  IGNORED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

  # Every column type the schema dumper emits for PostgreSQL. Unknown types
  # raise rather than being recorded as whatever they were called.
  COLUMN_TYPES = %i[
    bigint binary bit bit_varying boolean box cidr circle citext date daterange
    datetime decimal enum float hstore inet int4range int8range integer interval
    json jsonb line lseg ltree macaddr money numrange oid path point polygon
    primary_key serial bigserial string text time timestamp timestamptz tsrange
    tstzrange tsvector uuid virtual xml
  ].freeze

  # PR #1188 review: the live catalog reports these differently from how the
  # dumper writes them — serial/bigserial read back as an integer with a
  # sequence default, a virtual column as its underlying type — and
  # SchemaDriftService#live_type does not normalise them. None is in schema.rb
  # today. Refusing them HERE fails in development and CI, where schema.rb is
  # first read; a silent misread would instead refuse a production boot.
  UNSUPPORTED_TYPES = %i[serial bigserial virtual].freeze

  DEFINE = /\AActiveRecord::Schema\[[\d.]+\]\.define\(version:\s*([\d_]+)\)\s+do\s*\n/

  def self.load(path) = new(File.read(path.to_s), path: path.to_s)

  attr_reader :version, :tables, :foreign_keys, :extensions, :path

  def initialize(source, path: "(schema.rb)")
    @path = path
    @tables = {}
    @foreign_keys = []
    @extensions = []

    body, first_line = extract_body(source)
    Recorder.new(self).instance_eval(body, path, first_line)

    raise ArgumentError, "#{path} declares no tables — refusing a definition that would match anything" if @tables.empty?
  end

  # The dumper writes `pg_catalog.plpgsql`; a live database may report
  # `plpgsql`. The schema qualifier is not part of the extension's identity.
  def self.extension_name(name) = name.to_s.split(".").last

  def table_names = tables.keys

  def foreign_keys_from(table) = foreign_keys.select { |fk| fk.from_table == table }

  # Records the DSL. Each method mirrors the signature the dumper emits.
  class Recorder
    def initialize(definition) = @definition = definition

    def enable_extension(name, **) = @definition.extensions << SchemaDefinition.extension_name(name)

    def create_table(name, **options)
      name = name.to_s
      table = TableRecorder.new(name)
      yield table if block_given?
      return if IGNORED_TABLES.include?(name)

      @definition.tables[name] = Table.new(
        name: name, options: options, columns: table.columns,
        indexes: table.indexes, check_constraints: table.check_constraints
      )
    end

    def add_foreign_key(from_table, to_table, **options)
      @definition.foreign_keys << ForeignKey.new(from_table: from_table.to_s, to_table: to_table.to_s, options: options)
    end

    def method_missing(name, *)
      raise NoMethodError, "schema.rb calls `#{name}`, which SchemaDefinition does not record — " \
                           "teach the recorder rather than let it be skipped"
    end

    def respond_to_missing?(*) = false
  end

  class TableRecorder
    attr_reader :columns, :indexes, :check_constraints

    def initialize(table)
      @table = table
      @columns = []
      @indexes = []
      @check_constraints = []
    end

    def column(name, type, **options)
      type = type.to_sym
      raise NoMethodError, "schema.rb declares #{@table}.#{name} as unknown type `#{type}`" unless COLUMN_TYPES.include?(type)
      if UNSUPPORTED_TYPES.include?(type)
        raise ArgumentError, "schema.rb declares #{@table}.#{name} as `#{type}`, which the drift comparison " \
                                   "cannot read correctly yet — teach SchemaDriftService#live_type before using it"
      end

      options = options.dup
      options[:default] = Expression.new(options[:default].call) if options[:default].respond_to?(:call)
      @columns << Column.new(name: name.to_s, type: type, options: options)
    end

    COLUMN_TYPES.each do |type|
      define_method(type) { |*names, **options| names.each { |n| column(n, type, **options) } }
    end

    def index(columns, name:, **options)
      @indexes << Index.new(table: @table, name: name.to_s, columns: columns, options: options)
    end

    def check_constraint(expression, **options) = @check_constraints << [ expression, options ]

    def method_missing(name, *)
      raise NoMethodError, "schema.rb calls `t.#{name}` in #{@table}, which SchemaDefinition does not record"
    end

    def respond_to_missing?(*) = false
  end

  private

  def extract_body(source)
    lines = source.lines
    start = lines.index { |l| l.match?(DEFINE) }
    raise ArgumentError, "#{path} has no `ActiveRecord::Schema[...].define(version: ...) do` block" unless start

    @version = lines[start][DEFINE, 1].delete("_").to_i
    finish = lines.rindex { |l| l.match?(/\Aend\s*\z/) }
    raise ArgumentError, "#{path}: the define block is not closed" unless finish && finish > start

    [ lines[(start + 1)...finish].join, start + 2 ]
  end
end
