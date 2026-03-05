class SspConversionJob < ApplicationJob
  queue_as :default

  def perform(document_id, file_path)
    document = SspDocument.find(document_id)
    document.update!(status: "processing")

    begin
      SspExcelParserService.new(document, file_path).parse
      document.update!(status: "completed")

      # Optionally send notification email
      # SspMailer.conversion_complete(document).deliver_later

    rescue StandardError => e
      document.update!(status: "failed", error_message: e.message)
      Rails.logger.error("SSP Conversion failed: #{e.message}")
      # SspMailer.conversion_failed(document, e.message).deliver_later
    ensure
      FileUtils.rm_f(file_path)
    end
  end
end
