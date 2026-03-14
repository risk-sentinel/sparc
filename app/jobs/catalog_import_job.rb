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

      catalog.update!(
        status: "completed",
        metadata_extra: (catalog.metadata_extra || {}).merge(
          "processing_stage"        => "complete",
          "processing_message"      => "Import complete",
          "processing_completed_at" => Time.current.iso8601
        )
      )
    rescue StandardError => e
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
      Rails.logger.error("Catalog import failed for catalog #{catalog_id}: #{e.message}")
    ensure
      FileUtils.rm_f(file_path)
    end
  end
end
