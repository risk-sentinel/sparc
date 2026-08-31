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
  # #968 — DELIBERATE swallow, and the one place a broad rescue is right.
  #
  # This is the FAILURE notification. It runs when a parse has already failed, so
  # the document is already marked failed and the operator already has that
  # signal; the mail is a courtesy on top. Letting SMTP being down, a bad
  # address, or a template error re-raise here would turn a handled parse failure
  # into an unhandled job crash — replacing a clear "your document failed to
  # parse" with a retry storm on the notification itself.
  #
  # `StandardError` rather than a list, deliberately: every mail-dispatch failure
  # mode is out of our control and none of them changes what the caller should
  # do. That is the test for a broad rescue — not "errors are inconvenient here",
  # but "no error this can raise is actionable".
  rescue StandardError => e
    Rails.logger.error(
      "[DocumentParseMailer] dispatch failed for document ##{document&.id}: #{e.message}"
    )
  end
end
