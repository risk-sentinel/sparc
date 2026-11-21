# frozen_string_literal: true

# Confirms a push (#1354) by pulling the document fresh from its registered
# address — never an address the push carried — and comparing:
#
#   the pulled bytes hash to what was pushed
#     → confirmed. The pulled version is the one received (ExchangePullService
#       stores it, or finds it already on record), marked push-confirmed.
#   they differ, or the address could not be reached
#     → unconfirmed. The pushed bytes are received as an unconfirmed push:
#       validated and stored like any version, flagged, never auto-accepted,
#       and waiting for a reviewer.
#
# The receipt records which, and why; the pushed bytes leave the receipt once
# it is decided.
#
# NIST SP 800-53: CA-3, SI-7 (integrity: the push is checked against the
# registered source), SC-23, AU-12.
class ExchangePushConfirmService
  def self.call(receipt) = new(receipt).call

  def initialize(receipt)
    @receipt = receipt
    @source = receipt.exchange_document_source
    @connection = receipt.exchange_connection
  end

  def call
    return @receipt unless @receipt.pending?
    return finish("unconfirmed", reason: "The document is no longer registered on the connection") unless @source

    pull = ExchangePullService.call(@source)
    if pull.ok? && pull.document&.sha256 == @receipt.sha256
      pull.document.update_columns(push_confirmed: true, updated_at: Time.current)
      finish("confirmed", document: pull.document)
    else
      reason = pull.ok? ? mismatch(pull.document) : "The registered address could not be pulled: #{pull.error}"
      finish("unconfirmed", reason: reason, document: store_pushed)
    end
  end

  private

  def mismatch(document)
    "The document at its registered address (SHA-256 #{document&.sha256&.first(12)}…) differs from what was pushed " \
      "(#{@receipt.sha256.first(12)}…)"
  end

  # The pushed bytes, received as an unconfirmed push. A version the stream
  # already holds is not stored again, and keeps what it was.
  def store_pushed
    bytes = @receipt.bytes
    return nil if bytes.nil?

    ReceivedDocumentService.call(
      boundary: @connection.authorization_boundary, bytes: bytes, source: "push", document_source: @source,
      format: @source.format, document_type: @source.document_type, push_confirmed: false,
      filename: File.basename(URI(@source.url).path.presence || "document"), content_type: @receipt.content_type
    ).document
  rescue ReceivedDocumentService::Error => e
    @store_error = e.message
    nil
  end

  def finish(status, reason: nil, document: nil)
    reason = [ reason, @store_error && "The pushed bytes were not stored: #{@store_error}" ].compact.join(". ").presence
    @receipt.update!(status: status, reason: reason, received_document: document, completed_at: Time.current)
    @receipt.file.purge if @receipt.file.attached?
    @connection.update_columns(last_push_status: status, updated_at: Time.current)
    AuditEvent.log(action: "exchange_push_#{status}", user: nil, subject: @connection,
                   metadata: { push_receipt_id: @receipt.id, document_source_id: @receipt.exchange_document_source_id,
                               sha256: @receipt.sha256, received_document_id: document&.id,
                               reason: reason&.slice(0, 300) }.compact)
    @receipt
  end
end
