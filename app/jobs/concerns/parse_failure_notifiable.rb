# frozen_string_literal: true

# #623 — shared dispatch for the parse-failure notification, used by both async
# failure paths (DocumentConversionJob rescue, StuckDocumentReaperJob#reap_failed).
# Guarded on SMTP so no delivery job is enqueued when email is disabled, and
# rescued so a notification failure never re-fails the job that owns the document.
module ParseFailureNotifiable
  private

  def notify_parse_failure(document)
    return unless SparcConfig.enable_smtp?

    DocumentParseMailer.parse_failed(document).deliver_later
  rescue StandardError => e
    Rails.logger.error(
      "[DocumentParseMailer] dispatch failed for document ##{document&.id}: #{e.message}"
    )
  end
end
