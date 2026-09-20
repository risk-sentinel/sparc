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
  include ParseFailureNotifiable

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
        raise DocumentParseError, "Document #{document_id} has no attached file (cannot parse)"
      end

      parser_class = registry.parser_map.fetch(document.file_type) do
        raise DocumentParseError, "Unsupported file type: #{document.file_type}"
      end

      # Pull bytes from Active Storage into a local tempfile, hand the
      # path to the parser. The block-form `open` auto-deletes the
      # tempfile when the block exits.
      document.file.open do |tempfile|
        parser_class.new(document, tempfile.path).parse
      end

      enrich_cdef_nist_mappings(document)
      reindex_cdef_regions(document)

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

      # #680: parsed source blobs are now RETAINED by default so a referenced
      # artifact never disappears out from under an exported document. Purge is
      # opt-in — set SPARC_PERSIST_S3_BLOB=false to restore purge-after-parse.
      # (Failures never reach this line — the blob is always retained on failure
      # so the user can retry / inspect.)
      if ENV["SPARC_PERSIST_S3_BLOB"].to_s.downcase == "false"
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
      # #623 — notify the uploader (gated on SMTP; no-op otherwise).
      notify_parse_failure(document)
    end
  end

  private

  # #1103 — resolve AWS Security Hub identifiers to NIST controls on the UPLOAD
  # path. Enrichment used to be private to AwsLabsCdefImportService, so it ran
  # only on the weekly AWS Labs refresh: a CDEF uploaded here parsed its
  # controls and left every one of them holding a Security Hub id with no NIST
  # reference, belonging to no NIST family. The controls were there; nothing
  # that groups by NIST could see them.
  #
  # Runs AFTER the parse and OUTSIDE its transaction, deliberately. A document
  # that parsed correctly must not be lost because a converter lookup failed —
  # so a failure here degrades the document (#968's partial-success contract)
  # instead of failing the import.
  def enrich_cdef_nist_mappings(document)
    return unless document.is_a?(CdefDocument)

    CdefNistEnrichmentService.new.enrich!(document)
    document.clear_nist_enrichment_failure!
  rescue StandardError => e
    # Recorded on the document, not only in the log — the whole point of #968
    # item 4 is that an operator must be able to SEE a degraded import.
    document.record_nist_enrichment_failure!(e)
    Rails.logger.error(
      "[DocumentConversionJob] NIST enrichment failed for CdefDocument #{document.id}: #{e.class} — #{e.message}"
    )
  end

  # #1103 — complete a region pairing whichever file arrived second.
  #
  # AWS publishes regions as their own component definition and services point
  # at it with `provided-by` links, so the dependency crosses files by design.
  # The indexer resolves those links against regions ALREADY indexed, and this
  # path uploads files in browser order as independent async jobs — so a service
  # uploaded before its regions CDEF stored no regions and nothing ever fixed
  # it. AwsLabsCdefImportService had both an ordering pass and a repair pass for
  # its own path; neither was reachable from here.
  #
  # Same partial-success reasoning as enrichment: a re-index failure must not
  # fail an import that otherwise succeeded, and the service records the
  # degradation on the document itself.
  def reindex_cdef_regions(document)
    return unless document.is_a?(CdefDocument)

    CdefRegionReindexService.new.call(document)
  rescue StandardError => e
    Rails.logger.error(
      "[DocumentConversionJob] region re-index failed for CdefDocument #{document.id}: #{e.class} — #{e.message}"
    )
  end

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
