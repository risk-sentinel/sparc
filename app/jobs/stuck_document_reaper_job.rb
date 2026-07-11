# Reaps documents that are stuck in a non-terminal state (#618).
#
# Two distinct stuck conditions, handled differently because they mean
# different things:
#
#   1. No attached file, still `pending` — a metadata-only create (e.g. the
#      API create path before #618's finalize fix, or any create that never
#      attaches a file). There is nothing to parse, so the correct terminal
#      state is `completed`. This also self-heals records created before the
#      finalize fix shipped.
#
#   2. Has an attached file, `pending`/`processing` past the threshold with NO
#      live SolidQueue execution — a genuinely stalled or never-started parse
#      (lost enqueue, dead worker, crashed job). The correct terminal state is
#      `failed`, with a visible error_message so the uploader isn't left staring
#      at a perpetual spinner.
#
# A document whose parse is legitimately still running (a live SolidQueue job
# references it) is left alone, even past the threshold — long parses are not
# failures.
#
# Scheduled in config/recurring.yml. Threshold is operator-tunable via
# SPARC_DOCUMENT_REAP_MINUTES (default 10).
#
# NIST: SI-11 (Error Handling — no silent indefinite-pending state),
#       AU-3 (every transition is logged with document + reason).
class StuckDocumentReaperJob < ApplicationJob
  include ParseFailureNotifiable

  queue_as :default

  def perform
    threshold = SparcConfig.document_reap_minutes.minutes.ago
    live = live_document_keys
    completed = 0
    failed = 0

    DocumentTypeRegistry::TYPES.each do |type_key, entry|
      klass = entry.document_class
      next unless klass.column_names.include?("status")

      klass.where(status: %w[pending processing])
           .where(klass.arel_table[:updated_at].lt(threshold))
           .find_each do |doc|
        has_file = doc.respond_to?(:file) && doc.file.attached?

        if !has_file
          # Nothing to parse — resolve to the terminal `completed` state.
          resolve_completed(doc, type_key)
          completed += 1
          next
        end

        # File-bearing: only reap if no live execution is still working it.
        next if live.include?([ type_key.to_s, doc.id ])

        reap_failed(doc, type_key, threshold)
        failed += 1
      end
    end

    Rails.logger.info(
      "[StuckDocumentReaper] swept stuck documents: completed=#{completed} failed=#{failed} " \
      "threshold_minutes=#{SparcConfig.document_reap_minutes}"
    )
    { completed: completed, failed: failed }
  end

  private

  def resolve_completed(doc, type_key)
    doc.update!(status: "completed")
    Rails.logger.info(
      "[DocumentLifecycle] event=completed reason=reaper_metadata_only " \
      "document_type=#{type_key} document_id=#{doc.id} job_id=none"
    )
  end

  def reap_failed(doc, type_key, threshold)
    message = "Parsing did not complete within #{SparcConfig.document_reap_minutes} minutes " \
              "and no active job was found; marked failed by the stuck-document reaper. Re-upload to retry."
    attrs = { status: "failed" }
    attrs[:error_message] = message if doc.respond_to?(:error_message)
    if doc.respond_to?(:metadata_extra)
      attrs[:metadata_extra] = (doc.metadata_extra || {}).merge(
        "processing_stage"     => "failed",
        "processing_message"   => "Stalled — reaped after timeout",
        "processing_failed_at" => Time.current.iso8601
      )
    end
    doc.update!(**attrs)
    Rails.logger.warn(
      "[DocumentLifecycle] event=reaped document_type=#{type_key} document_id=#{doc.id} " \
      "job_id=none reason=stalled_no_live_job"
    )
    # #623 — notify the uploader that their stalled upload was marked failed
    # (gated on SMTP; no-op otherwise).
    notify_parse_failure(doc)
  end

  # Set of [type_key_string, document_id] for every DocumentConversionJob that
  # SolidQueue still considers unfinished. Used to avoid reaping a parse that is
  # legitimately still running. Defensive: any inspection failure degrades to an
  # empty set (the threshold remains the primary guard), never an exception that
  # would abort the sweep.
  def live_document_keys
    keys = Set.new
    # table_exists? is a catalog lookup (won't poison a surrounding transaction
    # the way a SELECT against a missing table would) — covers test/dev envs
    # where the SolidQueue schema isn't loaded.
    return keys unless defined?(SolidQueue::Job) && SolidQueue::Job.table_exists?

    SolidQueue::Job.where(class_name: "DocumentConversionJob", finished_at: nil).find_each do |job|
      args = (job.arguments || {})["arguments"] || []
      type_key, document_id = args[0], args[1]
      keys << [ type_key.to_s, document_id ] if type_key && document_id
    end
    keys
  rescue => e
    Rails.logger.warn("[StuckDocumentReaper] SolidQueue inspection failed (#{e.message}); proceeding on threshold alone")
    Set.new
  end
end
