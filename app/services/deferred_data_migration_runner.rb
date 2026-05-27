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

  def execute(run, user:)
    klass = run.name.safe_constantize
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
    begin
      klass.new.up
    ensure
      DeferredDataMigration.idle!
    end

    run.update!(status: "completed", completed_at: Time.current)
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
