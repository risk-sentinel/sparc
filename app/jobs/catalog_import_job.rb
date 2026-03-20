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

      # The service may have resolved to a different catalog (by UUID match),
      # destroying the shell record. Use the service's resolved catalog going forward.
      catalog = stats[:catalog]

      # Run post-import quality checks
      catalog.reload
      catalog.update!(
        metadata_extra: (catalog.metadata_extra || {}).merge(
          "processing_stage"   => "validating",
          "processing_message" => "Checking catalog quality..."
        )
      )
      validation_result = CatalogImportValidationService.new(catalog).validate

      catalog.update!(
        status: "completed",
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
end
