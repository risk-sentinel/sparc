class ProfileConversionJob < ApplicationJob
  queue_as :default

  def perform(document_id, file_path)
    document = ProfileDocument.find(document_id)
    document.update!(status: "processing")

    begin
      parser = case document.file_type
      when "xccdf" then ProfileXccdfParserService.new(document, file_path)
      when "json"  then ProfileJsonParserService.new(document, file_path)
      else raise "Unsupported file type: #{document.file_type}"
      end

      parser.parse
      document.update!(status: "completed")
    rescue StandardError => e
      document.update!(status: "failed", error_message: e.message)
      Rails.logger.error("Profile conversion failed for document #{document_id}: #{e.message}")
    ensure
      FileUtils.rm_f(file_path)
    end
  end
end
