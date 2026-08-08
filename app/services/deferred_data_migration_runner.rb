# frozen_string_literal: true

# Executes pending deferred data migrations (v1.8.3). Invoked
# post-boot by `DeferredDataMigrationJob` (which is enqueued by a
# Rails initializer after Puma binds).
#
# Concurrency safety: acquires a PostgreSQL advisory lock before
# touching any rows. Other ECS tasks that boot at the same time will
# fail to acquire the lock and skip — no parallel execution against
# the same data set. The lock is released when the runner finishes
# (or its container dies — PG releases session-scoped locks on
# disconnect).
#
# Crash recovery: any row left in `running` state from a previous
# container crash is reset to `pending` once we hold the lock — at
# that point we know no other runner is touching it. Failed rows
# are retried automatically on the next boot.
#
# Observability:
#   - Structured JSON log line per phase (started / completed /
#     failed / lock_held_elsewhere) to STDOUT for CloudWatch ingest
#   - DataMigrationRun row updated to (status, started_at,
#     completed_at, records_processed, error_message) at each phase
#   - On completion: AuditEvent emitted with action
#     "data_migration_completed" so the operator can correlate
#     with the rest of the audit trail
class DeferredDataMigrationRunner
  # PostgreSQL advisory lock key — namespaced 64-bit integer unique
  # to this purpose. Picked from the high end of the int64 range so
  # it can't collide with sequence-derived values other locks might
  # use. Don't change this — concurrent containers must agree.
  ADVISORY_LOCK_KEY = 0x5DA7A_CDA7A_DA7A

  class LockUnavailable < StandardError; end

  def self.run_all_pending(user: nil)
    new.run_all_pending(user: user)
  end

  def run_all_pending(user: nil)
    with_advisory_lock do
      reset_stuck_running_rows!
      DataMigrationRun.where(status: %w[pending failed]).order(:created_at).each do |run|
        execute(run, user: user)
      end
    end
  rescue LockUnavailable
    emit_log(nil, "lock_held_elsewhere",
             note: "another container holds the advisory lock; skipping this boot")
    false
  end

  private

  # Resolve a migration class, loading its file if the constant is not already
  # defined.
  #
  # This is why deferred data migrations had NEVER executed on a normal boot.
  # `db/migrate` is not an autoload path, and the runner runs inside the Puma /
  # Solid Queue process — a DIFFERENT process from the `bundle exec rails
  # db:prepare` that loaded the migration file. So `safe_constantize` returned
  # nil, the row was marked "failed", and the deploy carried on reporting
  # success: `schema_migrations` already had the version, because the deferred
  # pattern records that at db:migrate time and defers only the body.
  #
  # It went unnoticed because the only prior deferred migration (#881) also had
  # a `before_validation` callback and a computed fallback, so its column was
  # populated anyway on every path that mattered. Nothing about the mechanism
  # worked; it was masked.
  #
  # Rails guarantees the filename matches the class name, so the class name is a
  # reliable key. Loading is attempted ONLY when the constant is missing, so the
  # in-process db:migrate path is unaffected.
  def resolve_migration_class(name)
    existing = name.safe_constantize
    return existing if existing

    require_migration_file(name)
    name.safe_constantize
  end

  def require_migration_file(name)
    suffix = "_#{name.underscore}.rb"

    Array(ActiveRecord::Migrator.migrations_paths).each do |dir|
      path = Dir.glob(Rails.root.join(dir, "*#{suffix}")).first
      next if path.nil?

      require path
      return true
    end
    false
  rescue StandardError => e
    # A migration file that raises on load must not take the whole runner down
    # with it — the row is marked failed by the caller, and the remaining
    # migrations still get their turn.
    Rails.logger.error("[DeferredDataMigrationRunner] could not load #{name}: #{e.class}: #{e.message}")
    false
  end

  def execute(run, user:)
    klass = resolve_migration_class(run.name)
    if klass.nil?
      run.update!(status: "failed", completed_at: Time.current,
                  error_message: "Class #{run.name} not loadable")
      emit_log(run, "failed",
               error: "Class #{run.name} not loadable")
      return
    end

    run.update!(status: "running", started_at: Time.current,
                completed_at: nil, error_message: nil)
    emit_log(run, "started")

    DeferredDataMigration.executing!
    result =
      begin
        klass.new.up
      ensure
        DeferredDataMigration.idle!
      end

    # `records_processed` was never written by anything — every migration
    # reported "completed, 0 records processed", so an operator could not tell a
    # successful run from a no-op, which is exactly the distinction they need
    # when checking whether an upgrade actually did its data work. A migration
    # that returns an Integer now has that count recorded; one that returns
    # anything else leaves the column untouched rather than lying with a zero.
    processed = result if result.is_a?(Integer)
    run.update!(status: "completed", completed_at: Time.current,
                **(processed ? { records_processed: processed } : {}))
    emit_log(run, "completed")
    emit_audit_event(run, user: user)
  rescue StandardError => e
    run.update!(status: "failed", completed_at: Time.current,
                error_message: "#{e.class}: #{e.message.to_s.truncate(500)}")
    emit_log(run, "failed", error: e.message)
  end

  # Once we have the advisory lock, no other runner is touching this
  # DB. Any row still in `running` state is from a previous crashed
  # container — reset to pending so the retry path picks it up.
  def reset_stuck_running_rows!
    stuck = DataMigrationRun.running.to_a
    return if stuck.empty?

    stuck.each do |run|
      run.update!(status: "pending",
                  error_message: "Previous run did not complete (container crash); restarting")
      emit_log(run, "stuck_reset")
    end
  end

  # Wraps the block in a session-scoped PostgreSQL advisory lock.
  # Returns true if the lock was acquired and the block ran;
  # raises LockUnavailable if another session holds the lock.
  def with_advisory_lock
    conn = ActiveRecord::Base.connection
    acquired = conn.select_value("SELECT pg_try_advisory_lock(#{ADVISORY_LOCK_KEY})")
    raise LockUnavailable unless acquired

    begin
      yield
      true
    ensure
      conn.execute("SELECT pg_advisory_unlock(#{ADVISORY_LOCK_KEY})")
    end
  end

  # Structured JSON to STDOUT for log aggregators. Mirrors the shape
  # the AuditEvent.log helper emits (single line, parseable).
  def emit_log(run, phase, error: nil, note: nil)
    payload = {
      deferred_data_migration: {
        name:             run&.name,
        phase:            phase,
        status:           run&.status,
        version:          run&.version,
        started_at:       run&.started_at&.iso8601,
        completed_at:     run&.completed_at&.iso8601,
        duration_seconds: run&.duration_seconds,
        records_processed: run&.records_processed,
        error:            error,
        note:             note
      }.compact
    }
    Rails.logger.info(payload.to_json)
  end

  def emit_audit_event(run, user:)
    AuditEvent.log(
      user: user,
      action: "data_migration_completed",
      metadata: {
        name:              run.name,
        version:           run.version,
        duration_seconds:  run.duration_seconds,
        records_processed: run.records_processed
      }
    )
  end
end
