# Background job for importing OSCAL catalog files.
#
# Lifecycle: pending → processing → completed / failed
# Cleanup:   ensure FileUtils.rm_f(file_path)
#
class CatalogImportJob < ApplicationJob
  queue_as :default

  def perform(catalog_id, file_path, original_filename)
    catalog = ControlCatalog.find(catalog_id)
    catalog.update!(status: "processing")

    begin
      file = File.open(file_path)
      stats = CatalogImportService.call(file, original_filename, existing_catalog: catalog)
      catalog.update!(status: "completed")
    rescue StandardError => e
      catalog.update!(status: "failed", error_message: e.message)
      Rails.logger.error("Catalog import failed for catalog #{catalog_id}: #{e.message}")
    ensure
      FileUtils.rm_f(file_path)
    end
  end
end
