# Unified conversion job that replaces SspConversionJob, SarConversionJob,
# and CdefConversionJob. Uses DocumentTypeRegistry to resolve the correct
# document class and parser service.
#
# Lifecycle: pending → processing → completed / failed
# Progress:  Writes processing stages to document.metadata_extra["processing_*"]
#            so the show page can display live stage messages via auto-refresh.
# Cleanup:   ensure FileUtils.rm_f(file_path)
#
class DocumentConversionJob < ApplicationJob
  queue_as :default

  def perform(document_type_key, document_id, file_path)
    registry = DocumentTypeRegistry.for(document_type_key)
    document = registry.document_class.find(document_id)

    # Record start time and set processing status
    document.update!(
      status: "processing",
      metadata_extra: (document.metadata_extra || {}).merge(
        "processing_stage"      => "starting",
        "processing_message"    => "Preparing to process file...",
        "processing_started_at" => Time.current.iso8601
      )
    )

    begin
      parser_class = registry.parser_map.fetch(document.file_type) do
        raise "Unsupported file type: #{document.file_type}"
      end

      parser_class.new(document, file_path).parse

      document.update!(
        status: "completed",
        metadata_extra: (document.metadata_extra || {}).merge(
          "processing_stage"        => "complete",
          "processing_message"      => "Processing complete",
          "processing_completed_at" => Time.current.iso8601
        )
      )
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
      Rails.logger.error("#{document_type_key} conversion failed for document #{document_id}: #{e.message}")
    ensure
      FileUtils.rm_f(file_path)
    end
  end
end
