# Unified conversion job that replaces SspConversionJob, TprConversionJob,
# and ProfileConversionJob. Uses DocumentTypeRegistry to resolve the correct
# document class and parser service.
#
# Lifecycle: pending → processing → completed / failed
# Cleanup:   ensure FileUtils.rm_f(file_path)
#
class DocumentConversionJob < ApplicationJob
  queue_as :default

  def perform(document_type_key, document_id, file_path)
    registry = DocumentTypeRegistry.for(document_type_key)
    document = registry.document_class.find(document_id)

    document.update!(status: "processing")

    begin
      parser_class = registry.parser_map.fetch(document.file_type) do
        raise "Unsupported file type: #{document.file_type}"
      end

      parser_class.new(document, file_path).parse
      document.update!(status: "completed")
    rescue StandardError => e
      document.update!(status: "failed", error_message: e.message)
      Rails.logger.error("#{document_type_key} conversion failed for document #{document_id}: #{e.message}")
    ensure
      FileUtils.rm_f(file_path)
    end
  end
end
