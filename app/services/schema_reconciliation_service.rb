# frozen_string_literal: true

# #1151 — bring a database that is BEHIND schema.rb up to it, additively.
#
#   SchemaReconciliationService.new.call                # apply
#   SchemaReconciliationService.new(dry_run: true).call # run, capture, roll back
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# Squashing continues (owner-decided 2026-09-19), and every squash archives
# migrations. `db:migrate` never runs a migration it cannot see, so a
# deployment that had not yet run an archived one ends with no pending
# migrations and a schema missing whatever it would have created. That is how
# v1.16.2 shipped un-upgradable (#1147), and v1.16.3's repair was a
# hand-written list of seven columns — correct, and stale the moment the next
# squash archives something else.
#
# This generates the repair from `schema.rb` at the moment it runs, the same
# principle `bin/schema_drift_sql` already applied to the CHECK: a generator
# cannot go stale, because it reads the schema instead of remembering it.
#
# ── What it will and will not do ───────────────────────────────────────────
#
# ADDITIVE ONLY: create a missing extension, table, column, index or foreign
# key. It never drops, renames, retypes or rewrites. A database with drift it
# cannot fix by adding (a column of the wrong type, say) needs a human and a
# migration, and guessing would turn a failed deploy into lost data.
#
# ALL OR NOTHING: every statement runs in ONE transaction — PostgreSQL DDL is
# transactional — so it either reconciles completely or changes nothing. It
# REFUSES, applying nothing, when:
#   - any structural drift is not reconcilable (a column_type mismatch), or
#   - an addition is unsafe: a NOT NULL column with no default on a table that
#     already has rows, which PostgreSQL would reject part-way anyway, or
#   - a statement fails (a unique index over duplicate data, a foreign key over
#     orphaned rows) — the transaction rolls back and the error is the reason.
#
# It is NOT a second schema path that can drift from `schema.rb` — the concern
# #1151 raised against a squash that applies DDL — because `schema.rb` is its
# only input: it builds exactly what `db:schema:load` would, and nothing else.
#
# NIST SP 800-53 Rev 5: CM-3 (configuration change control — each statement is
# recorded), SI-7 (software, firmware and information integrity — the schema is
# brought to its declared state or the container does not start), AU-2/AU-12
# (the reconciliation is an audited event).
class SchemaReconciliationService
  Result = Struct.new(:status, :statements, :reasons, :drift, keyword_init: true) do
    def clean? = status == :clean
    def reconciled? = status == :reconciled
    def planned? = status == :planned
    def refused? = status == :refused

    def report
      case status
      when :clean then "schema reconciliation: nothing to do — the database matches db/schema.rb"
      when :refused
        [ "schema reconciliation REFUSED — nothing was changed:", *reasons.map { |r| "  - #{r}" } ].join("\n")
      else
        verb = planned? ? "would run" : "ran"
        [ "schema reconciliation #{verb} #{statements.size} statement(s) for #{drift.size} difference(s):",
          *statements.map { |s| "  #{s}" } ].join("\n")
      end
    end
  end

  # Statements a transaction wraps around the DDL, which say nothing about
  # what was changed. Everything else the connection executed is recorded.
  NOISE = /\A\s*(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT|SELECT|SHOW|SET)\b/i

  class Refused < StandardError; end

  def initialize(dry_run: false, drift_service: SchemaDriftService.new, connection: ActiveRecord::Base.connection,
                 audit: true)
    @dry_run = dry_run
    @drift_service = drift_service
    @connection = connection
    @audit = audit
  end

  # Session-level advisory lock, the same device `db:migrate` uses for its own
  # migrations. Any stable bigint; "SPARC" + #1151.
  LOCK_ID = 0x5CA7_1151

  # PR #1188 review: several web tasks booting at once would each see the same
  # missing column and each run ADD COLUMN; every one but the first then fails
  # "already exists", records a false `schema_reconciliation_refused`, and exits
  # its container — which a deployment circuit breaker could read as a failed
  # deploy. So the whole check-and-repair is serialised, and the drift is
  # measured only AFTER the lock is held: a task that waited finds the schema
  # already repaired and reports clean.
  def call
    with_lock { reconcile }
  end

  private

  def reconcile
    drift = drift_service.drift
    return Result.new(status: :clean, statements: [], reasons: [], drift: []) if drift.empty?

    reasons = refusal_reasons(drift)
    return finish(Result.new(status: :refused, statements: [], reasons: reasons, drift: drift)) if reasons.any?

    statements = execute(drift)
    finish(Result.new(status: dry_run ? :planned : :reconciled, statements: statements, reasons: [], drift: drift))
  rescue Refused, ActiveRecord::ActiveRecordError => e
    finish(Result.new(status: :refused, statements: [], reasons: [ e.message ], drift: drift || []))
  end

  def with_lock
    connection.select_value("SELECT pg_advisory_lock(#{LOCK_ID})")
    yield
  ensure
    connection.select_value("SELECT pg_advisory_unlock(#{LOCK_ID})")
  end

  attr_reader :dry_run, :drift_service, :connection

  def definition = drift_service.definition

  def refusal_reasons(drift)
    unfixable = drift.reject(&:reconcilable?).map { |d| "#{d} — not additive; needs a migration" }
    unfixable + drift.select { |d| d.kind == :column }.filter_map { |d| unsafe_column_reason(d) }
  end

  # PostgreSQL fills a new column's existing rows with its default, so a
  # default makes NOT NULL safe. Without one, a populated table cannot take it.
  def unsafe_column_reason(drift)
    column = definition.tables.fetch(drift.table).column(drift.name)
    return if column.null? || column.default?
    return unless connection.select_value("SELECT EXISTS (SELECT 1 FROM #{connection.quote_table_name(drift.table)})")

    "missing column #{drift.table}.#{drift.name} is NOT NULL with no default, and #{drift.table} has rows — " \
      "it needs a migration that backfills it"
  end

  # Order matters: an extension before the index that uses it, a table before
  # the columns and indexes on it, every table before the foreign keys
  # between them.
  def execute(drift)
    by_kind = drift.group_by(&:kind)
    statements = []
    capture(statements) do
      # `requires_new:` — without it a transaction nested in another (a caller's,
      # or the spec suite's) swallows ActiveRecord::Rollback and a DRY RUN would
      # silently apply. A savepoint makes the rollback real at any depth.
      connection.transaction(requires_new: true) do
        Array(by_kind[:extension]).each { |d| connection.enable_extension(d.name) }
        Array(by_kind[:table]).each { |d| create_table(definition.tables.fetch(d.table)) }
        Array(by_kind[:column]).each { |d| add_column(d) }
        Array(by_kind[:check_constraint]).each { |d| add_check_constraint(d) }
        Array(by_kind[:index]).each { |d| add_index(index_for(d)) }
        Array(by_kind[:foreign_key]).each { |d| add_foreign_key(d) }
        raise ActiveRecord::Rollback if dry_run
      end
    end
    statements
  end

  def create_table(table)
    options = table.options.except(:force)
    connection.create_table(table.name, **options) do |t|
      table.columns.each { |c| t.column(c.name, c.type, **column_options(c)) }
    end
    table.indexes.each { |index| add_index(index) }
    table.check_constraints.each { |expression, opts| connection.add_check_constraint(table.name, expression, **opts) }
  end

  def add_column(drift)
    column = definition.tables.fetch(drift.table).column(drift.name)
    connection.add_column(drift.table, column.name, column.type, **column_options(column))
  end

  def column_options(column)
    options = column.options.dup
    options[:default] = column.default.to_proc if column.default.is_a?(SchemaDefinition::Expression)
    options
  end

  def add_check_constraint(drift)
    expression, options = definition.tables.fetch(drift.table).check_constraints.find { |_e, o| o[:name].to_s == drift.name }
    raise Refused, "no check constraint in schema.rb matches #{drift}" unless expression

    connection.add_check_constraint(drift.table, expression, **options)
  end

  def index_for(drift) = definition.tables.fetch(drift.table).indexes.find { |i| i.name == drift.name }

  def add_index(index)
    connection.add_index(index.table, index.columns, name: index.name, **index.options)
  end

  def add_foreign_key(drift)
    fk = definition.foreign_keys.find do |f|
      f.from_table == drift.table && f.to_table == drift.expected &&
        (f.options[:column] || "#{f.to_table.singularize}_id").to_s == drift.name
    end
    raise Refused, "no foreign key in schema.rb matches #{drift}" unless fk

    connection.add_foreign_key(fk.from_table, fk.to_table, **fk.options)
  end

  # The SQL the adapter actually sent, not a description of it: this is the
  # record an auditor reads, so it is the statements, verbatim.
  def capture(into)
    callback = lambda do |*, payload|
      sql = payload[:sql].to_s
      into << sql.squish unless sql.match?(NOISE) || payload[:name] == "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
  end

  def finish(result)
    audit!(result) if @audit && !result.clean? && !result.planned?
    result
  end

  # A failed audit write must not mask the reconciliation's own outcome — and
  # at boot the audit table may be one of the things that was just created.
  def audit!(result)
    AuditEvent.log(
      action: result.reconciled? ? "schema_reconciled" : "schema_reconciliation_refused",
      metadata: {
        app_version: SparcConfig.version,
        schema_rb_version: definition.version,
        migration_version: connection.select_value("SELECT MAX(version) FROM schema_migrations"),
        drift: result.drift.map(&:to_s),
        statements: result.statements,
        reasons: result.reasons
      }
    )
  rescue StandardError => e
    Rails.logger.error("schema reconciliation: could not write the audit event (#{e.class}: #{e.message})")
  end
end
