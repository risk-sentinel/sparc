class TprConversionJob < ApplicationJob
  queue_as :default

  def perform(document_id, file_path)
    document = TprDocument.find(document_id)
    document.update!(status: "processing")

    begin
      TprExcelParserService.new(document, file_path).parse
      document.update!(status: "completed")

    rescue StandardError => e
      document.update!(status: "failed", error_message: e.message)
      Rails.logger.error("TPR Conversion failed: #{e.message}")
    end
  end
end
