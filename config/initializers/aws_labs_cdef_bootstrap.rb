# frozen_string_literal: true

# Issue #487 — Bootstrap the AWS Labs CDEF catalog on first deploy.
#
# The recurring `AwsLabsCdefRefreshJob` schedule fires weekly at 06:00 UTC,
# which means a fresh deploy with `SPARC_AWS_LABS_CDEF_ENABLED=true` waits up
# to 7 days for the first ingest. In production environments where shell
# access is restricted (e.g., ECS Exec banned per sparc-iac #243), the
# `bin/rails aws_labs:cdefs:import` workaround isn't reachable.
#
# This initializer enqueues `AwsLabsCdefRefreshJob` once on boot when:
#   - The feature is enabled (`SPARC_AWS_LABS_CDEF_ENABLED=true`)
#   - No AWS-Labs-sourced rows exist yet (`source_type = 'aws_labs'`)
#
# Subsequent boots are no-ops because the rows exist. Clones (user_upload
# rows with `cloned_from_id` set) are filtered out by the `aws_labs_sourced`
# scope, so a tenant with only cloned-and-edited rows still triggers
# bootstrap — which is the correct behavior (the canonical AWS rows are
# what should populate, and clones survive across refreshes anyway).
Rails.application.config.after_initialize do
  next unless SparcConfig.aws_labs_cdef_enabled?
  next if Rails.env.test?
  next if defined?(Rails::Console)
  # Operator escape hatch (e.g., for one-off boot-from-snapshot scenarios
  # where the operator wants to disable auto-bootstrap without flipping
  # the main feature flag).
  next if ActiveModel::Type::Boolean.new.cast(ENV["SPARC_SKIP_AWS_LABS_BOOTSTRAP"])

  ActiveSupport.on_load(:active_record) do
    # Guard against pre-migration boots and during the migration squash
    # window where the table may not yet exist.
    next unless ActiveRecord::Base.connection.table_exists?(:cdef_documents)
    next if CdefDocument.aws_labs_sourced.exists?

    Rails.logger.info(
      "[AwsLabsCdefBootstrap] SPARC_AWS_LABS_CDEF_ENABLED=true and catalog is empty; " \
      "enqueueing AwsLabsCdefRefreshJob for initial ingest."
    )
    AwsLabsCdefRefreshJob.perform_later
  rescue ActiveRecord::ActiveRecordError => e
    # Don't take the app down if the bootstrap check fails (e.g., DB
    # not yet reachable during a slow ECS task start). The weekly
    # recurring schedule remains the safety net.
    Rails.logger.warn(
      "[AwsLabsCdefBootstrap] Skipped initial enqueue due to ActiveRecord error: " \
      "#{e.class}: #{e.message}"
    )
  end
end
