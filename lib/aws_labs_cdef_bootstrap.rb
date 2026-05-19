# frozen_string_literal: true

# Issue #487 / #492 — Bootstrap the AWS Labs CDEF catalog on first deploy.
#
# Background:
#   The recurring AwsLabsCdefRefreshJob fires weekly, so a fresh deploy with
#   SPARC_AWS_LABS_CDEF_ENABLED=true waits up to 7 days for the first
#   ingest. This module is invoked from
#   config/initializers/aws_labs_cdef_bootstrap.rb (via Rails.application.config.to_prepare)
#   to enqueue the job once when the catalog is empty.
#
# Why the logic lives here, not directly in the initializer:
#
#   - **#492 defect 1 (autoload NameError)**: the previous implementation
#     referenced `CdefDocument` inside `after_initialize`, which could be
#     reached while `ApplicationRecord` was still autoloading (e.g., from
#     a rake task that loads `User`, which inherits from ApplicationRecord).
#     Extracting to a module called via `to_prepare` means the model layer
#     is fully loaded before we touch any AR constants.
#
#   - **#492 defect 2 (3x firing per container boot)**: each Rails boot
#     re-fires the initializer. In prod, rake tasks + the seed runner +
#     Puma each boot Rails separately, producing three enqueue events
#     for the same logical bootstrap. We dedupe via a Rails.cache lock
#     (Solid Cache in prod -> cross-process; memory_store in dev ->
#     per-process; :null_store in test -> bypassed).
#
#   - The module is directly testable without replicating gating logic
#     in specs.
module AwsLabsCdefBootstrap
  module_function

  LOCK_KEY = "aws_labs_cdef_bootstrap:fired"
  LOCK_TTL = 1.hour

  # Run the bootstrap check. Returns a symbol describing the outcome --
  # useful for tests + logs. Never raises; DB errors are swallowed and
  # logged at warn level so the recurring schedule remains the safety net.
  def run!
    return :skipped_disabled        unless SparcConfig.aws_labs_cdef_enabled?
    return :skipped_test_env        if Rails.env.test?
    return :skipped_console         if defined?(Rails::Console)
    return :skipped_env_override    if env_override_set?
    return :skipped_table_missing   unless table_exists?
    return :skipped_already_populated if already_populated?
    return :skipped_lock_held       if lock_held?

    acquire_lock!
    Rails.logger.info(
      "[AwsLabsCdefBootstrap] SPARC_AWS_LABS_CDEF_ENABLED=true and catalog is empty; " \
      "enqueueing AwsLabsCdefRefreshJob for initial ingest."
    )
    AwsLabsCdefRefreshJob.perform_later
    :enqueued
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn(
      "[AwsLabsCdefBootstrap] Skipped initial enqueue due to ActiveRecord error: " \
      "#{e.class}: #{e.message}"
    )
    :skipped_db_error
  end

  def env_override_set?
    ActiveModel::Type::Boolean.new.cast(ENV["SPARC_SKIP_AWS_LABS_BOOTSTRAP"])
  end

  def table_exists?
    ActiveRecord::Base.connection.table_exists?(:cdef_documents)
  end

  def already_populated?
    CdefDocument.aws_labs_sourced.exists?
  end

  def lock_held?
    Rails.cache.exist?(LOCK_KEY)
  end

  def acquire_lock!
    Rails.cache.write(LOCK_KEY, Time.current.iso8601, expires_in: LOCK_TTL)
  end

  # Test helper: release the lock so a subsequent run! call in the same
  # process can proceed. Not used in production code paths.
  def release_lock!
    Rails.cache.delete(LOCK_KEY)
  end
end
