# frozen_string_literal: true

# #1354 — a provider's push: "this registered document changed".
#
#   POST /api/v1/exchange_connections/:exchange_connection_id/document_sources/:id/push
#
#   Body:     the document itself (FedRAMP or OSCAL JSON, HDF JSON, XCCDF XML)
#   Headers:  SPARC-Push-Timestamp   Unix seconds when it was signed
#             SPARC-Push-Signature   base64 Ed25519 signature over
#                                    ExchangePushService.signed_message
#
#   202  accepted; SPARC pulls the document fresh from its registered address
#        to confirm it (the receipt's status says how that went)
#   400  no document · 401 not accepted · 409 already received · 413 too large
#
# No API token: the signature, checked against the Ed25519 keys pinned on the
# connection, is the credential (ExchangePushService). That is why this
# controller stands outside Api::V1::BaseController. It reads no session or
# cookie, so there is nothing for a forged cross-site request to ride on.
# Requests are rate-limited in Rack::Attack ("exchange/pushes").
#
# NIST SP 800-53: CA-3, SC-23, AU-10, IA-9, AC-3, SC-5, AU-12.
class Api::V1::ExchangePushesController < ActionController::API
  TIMESTAMP_HEADER = "SPARC-Push-Timestamp"
  SIGNATURE_HEADER = "SPARC-Push-Signature"

  def create
    return refuse_too_large if request.content_length.to_i > SparcConfig.max_upload_bytes

    receipt = ExchangePushService.call(
      connection_id: params[:exchange_connection_id], document_source_id: params[:id],
      body: request.body.read(SparcConfig.max_upload_bytes + 1), timestamp: request.headers[TIMESTAMP_HEADER],
      signature: request.headers[SIGNATURE_HEADER], remote_ip: request.remote_ip,
      content_type: request.media_type
    )
    render json: { data: self.class.serialize(receipt) }, status: :accepted
  rescue ExchangePushService::Refused => e
    render json: { error: e.message }, status: e.status
  end

  def self.serialize(receipt)
    {
      id: receipt.id,
      exchange_connection_id: receipt.exchange_connection_id,
      exchange_document_source_id: receipt.exchange_document_source_id,
      status: receipt.status,
      reason: receipt.reason,
      sha256: receipt.sha256,
      byte_size: receipt.byte_size,
      key_fingerprint: receipt.key_fingerprint,
      signed_at: receipt.signed_at&.utc&.iso8601,
      received_at: receipt.created_at&.utc&.iso8601,
      completed_at: receipt.completed_at&.utc&.iso8601,
      received_document_id: receipt.received_document_id
    }
  end

  private

  # Refused before the body is read, and audited like every other refusal.
  def refuse_too_large
    AuditEvent.log(action: "exchange_push_refused", metadata: {
                     reason: "too_large", connection_id: params[:exchange_connection_id].to_s.first(20),
                     document_source_id: params[:id].to_s.first(20), remote_ip: request.remote_ip,
                     byte_size: request.content_length.to_i
                   })
    render json: { error: "The document exceeds the #{SparcConfig.max_upload_bytes}-byte limit" },
           status: :content_too_large
  end
end
