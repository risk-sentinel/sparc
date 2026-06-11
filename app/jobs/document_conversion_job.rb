# Unified conversion job that replaces SspConversionJob, SarConversionJob,
# and CdefConversionJob. Uses DocumentTypeRegistry to resolve the correct
# document class and parser service.
#
# Lifecycle: pending → processing → completed / failed
# Progress:  Writes processing stages to document.metadata_extra["processing_*"]
#            so the show page can display live stage messages via auto-refresh.
#
# #392: source bytes come from Active Storage instead of a local tmp path.
# `document.file.open` downloads the blob into the Sidekiq container's
# tmpdir and yields a path; the parser API is unchanged. The previous
# local-tmp-path approach broke in multi-task ECS deployments where the
# Sidekiq container couldn't see the file the web container wrote.
#
# Retention: by default the original blob is purged after a successful parse
# (parsed OSCAL data lives in RDS — the blob is redundant). Set
# SPARC_PERSIST_S3_BLOB=true to keep originals for audit / re-parse /
# OSCAL byte-for-byte round-trip diffs. Failed parses ALWAYS retain the
# blob so the user can retry / inspect.
#
class DocumentConversionJob < ApplicationJob
  queue_as :default

  # #392: transient S3 / network errors get auto-retried with backoff.
  # Permanent errors (parser failures, missing attachment) still flip the
  # document to "failed" via the rescue below.
  retry_on Aws::Errors::ServiceError,
           wait: :polynomially_longer, attempts: 5
  retry_on Net::OpenTimeout, Net::ReadTimeout,
           wait: :polynomially_longer, attempts: 5

  # The third positional arg is retained for one release cycle so jobs
  # enqueued before the deploy (which still pass a tmp file_path) can drain
  # without ArgumentError. It is intentionally ignored.
  def perform(document_type_key, document_id, _legacy_file_path = nil)
    registry = DocumentTypeRegistry.for(document_type_key)
    document = registry.document_class.find(document_id)

    document.update!(
      status: "processing",
      metadata_extra: (document.metadata_extra || {}).merge(
        "processing_stage"      => "starting",
        "processing_message"    => "Preparing to process file...",
        "processing_started_at" => Time.current.iso8601
      )
    )
    log_lifecycle("started", document_type_key, document_id)

    begin
      unless document.file.attached?
        raise "Document #{document_id} has no attached file (cannot parse)"
      end

      parser_class = registry.parser_map.fetch(document.file_type) do
        raise "Unsupported file type: #{document.file_type}"
      end

      # Pull bytes from Active Storage into a local tempfile, hand the
      # path to the parser. The block-form `open` auto-deletes the
      # tempfile when the block exits.
      document.file.open do |tempfile|
        parser_class.new(document, tempfile.path).parse
      end

      # Auto-publish resolved profile catalogs (NIST-published baselines)
      auto_publish = document.metadata_extra&.dig("auto_publish")
      lifecycle = auto_publish ? "published" : "in_progress"

      attrs = {
        status: "completed",
        lifecycle_status: lifecycle,
        metadata_extra: (document.metadata_extra || {}).merge(
          "processing_stage"        => "complete",
          "processing_message"      => auto_publish ? "Resolved profile imported and published" : "Processing complete",
          "processing_completed_at" => Time.current.iso8601
        )
      }

      # Set published timestamp for auto-published documents
      if auto_publish
        attrs[:published] = Time.current.iso8601
        attrs[:profile_version] = document.profile_version.presence || "1.0.0" if document.respond_to?(:profile_version)
      end

      document.update!(**attrs)
      log_lifecycle("succeeded", document_type_key, document_id)

      # #392: drop the redundant S3 blob unless the operator opted in to
      # persistence. Failures don't reach this line — the blob is retained
      # on failure so the user can retry / inspect.
      unless ENV["SPARC_PERSIST_S3_BLOB"].to_s.downcase == "true"
        document.file.purge_later
      end
    rescue StandardError => e
      failed_stage = document.reload.metadata_extra&.dig("processing_stage") || "unknown"
      document.update!(
        status: "failed",
        error_message: e.message,
        metadata_extra: (document.metadata_extra || {}).merge(
          "processing_stage"     => "failed",
          "processing_message"   => "Failed during: #{failed_stage}",
          "processing_failed_at" => Time.current.iso8601
        )
      )
      log_lifecycle("failed", document_type_key, document_id, error: e.message)
      Rails.logger.error("#{document_type_key} conversion failed for document #{document_id}: #{e.message}")
    end
  end

  private

  # #618 — structured, greppable lifecycle log for the parse pipeline. Pairs
  # with the `enqueued` line emitted at the enqueue site (FileUploadable) and
  # the reaper's `reaped` line, so a document's whole journey
  # (enqueued → started → succeeded|failed|reaped) is traceable in CloudWatch
  # by document_id. NIST: AU-3 (Content of Audit Records).
  def log_lifecycle(event, document_type_key, document_id, error: nil)
    line = "[DocumentLifecycle] event=#{event} document_type=#{document_type_key} " \
           "document_id=#{document_id} job_id=#{job_id}"
    line += " error=#{error.inspect}" if error
    if event == "failed"
      Rails.logger.warn(line)
    else
      Rails.logger.info(line)
    end
  end
end
