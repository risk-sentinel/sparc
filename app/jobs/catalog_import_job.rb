# Background job for importing OSCAL catalog files.
#
# Lifecycle: pending → processing → completed / failed
# Progress:  Writes processing stages to catalog.metadata_extra["processing_*"]
#            so the show page can display live stage messages via auto-refresh.
# Cleanup:   ensure FileUtils.rm_f(file_path)
#
class CatalogImportJob < ApplicationJob
  queue_as :default

  def perform(catalog_id, file_path, original_filename)
    catalog = ControlCatalog.find(catalog_id)
    # #1235 — the URL the upload redirected to, and the processing page polls.
    url_uuid = catalog.oscal_uuid

    catalog.update!(
      status: "processing",
      metadata_extra: (catalog.metadata_extra || {}).merge(
        "processing_stage"      => "starting",
        "processing_message"    => "Preparing to import catalog...",
        "processing_started_at" => Time.current.iso8601
      )
    )

    begin
      file = File.open(file_path)
      stats = CatalogImportService.call(file, original_filename, existing_catalog: catalog)

      # The service may have resolved to a different catalog (by UUID match).
      # If so, clean up the shell record and use the resolved catalog going forward.
      resolved_catalog = stats[:catalog]
      if resolved_catalog.id != catalog.id
        # Recorded before the placeholder goes, so its address never resolves
        # to nothing.
        remember_upload_url!(resolved_catalog, url_uuid)
        catalog.destroy if catalog.control_families.empty?
        catalog = resolved_catalog
      end

      # Run post-import quality checks
      catalog.reload
      catalog.update!(
        metadata_extra: (catalog.metadata_extra || {}).merge(
          "processing_stage"   => "validating",
          "processing_message" => "Checking catalog quality..."
        )
      )
      validation_result = CatalogImportValidationService.new(catalog).validate

      # #1235 — an upload lands as Draft, a re-import into an existing catalog
      # included (owner, 2026-10-21): the user reviews the warnings and
      # publishes through `publish`, so the approval gate applies.
      catalog.update!(
        status: "completed",
        lifecycle_status: "in_progress",
        metadata_extra: (catalog.metadata_extra || {}).merge(
          validation_result,
          "processing_stage"        => "complete",
          "processing_message"      => "Import complete",
          "processing_completed_at" => Time.current.iso8601
        )
      )
    rescue StandardError => e
      # Reload catalog — it may have been swapped by the service
      catalog = ControlCatalog.find_by(id: catalog_id) || ControlCatalog.find_by(id: stats&.dig(:catalog)&.id)
      if catalog
        failed_stage = catalog.reload.metadata_extra&.dig("processing_stage") || "unknown"
        catalog.update!(
          status: "failed",
          error_message: e.message,
          metadata_extra: (catalog.metadata_extra || {}).merge(
            "processing_stage"     => "failed",
            "processing_message"   => "Failed during: #{failed_stage}",
            "processing_failed_at" => Time.current.iso8601
          )
        )
      end
      Rails.logger.error("Catalog import failed for catalog #{catalog_id}: #{e.message}")
    ensure
      FileUtils.rm_f(file_path)
    end
  end

  private

  # #1235 — the upload redirects to its placeholder record's random uuid, and
  # the processing page polls that URL. When the import resolves to the
  # catalog that already owns the file's uuid, the placeholder is deleted and
  # the next poll found nothing: "Catalog not found — it may have been merged
  # during re-import". The owner records the placeholder's uuid, so
  # ControlCatalog.find_for_url resolves it. (When the placeholder itself is
  # given the file's uuid, ControlCatalog#remember_superseded_oscal_uuid
  # records the old one in the same save.)
  def remember_upload_url!(catalog, url_uuid)
    return if url_uuid.blank? || catalog.oscal_uuid == url_uuid

    extra = catalog.metadata_extra || {}
    superseded = (Array(extra["superseded_oscal_uuids"]) | [ url_uuid ])
    catalog.update!(metadata_extra: extra.merge("superseded_oscal_uuids" => superseded))
  end
end
