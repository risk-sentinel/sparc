# frozen_string_literal: true

require "base64"
require "digest"
require "ipaddr"
require "stringio"

# Receives a provider's push (#1354): a signed notice that one registered
# document of a connection changed, carrying the document's bytes.
#
# The request is the credential. It is accepted only when every check holds:
#
#   - the connection exists, is enabled and has an Ed25519 key pinned;
#   - the document is one registered on that connection, and enabled;
#   - the caller's address is inside the connection's IP ranges, when it
#     has any;
#   - the body is not empty and within the upload limit;
#   - the timestamp is within 5 minutes of SPARC's clock;
#   - the signature verifies against a pinned key, over
#
#         SPARC-PUSH-1
#         <connection id>
#         <document source id>
#         <timestamp, as sent>
#         <hex SHA-256 of the body>
#
#     joined by "\n" with no trailing newline;
#   - that signature has not been accepted before (replay).
#
# An accepted push is recorded as an ExchangePushReceipt and confirmed by a
# fresh pull from the registered address (ExchangePushConfirmJob). Any
# address the provider might put in a push is never read: the body is the
# document, and the address is the one registered here.
#
# Every refusal is audited with its reason; the caller is told only that the
# push was not accepted, so the response cannot be used to probe which
# connections or documents exist.
#
# NIST SP 800-53: CA-3, SC-23 (session authenticity: signed, time-bounded,
# replay-proof), AU-10 (non-repudiation: which pinned key signed), IA-9
# (service identification), AC-3, SC-5 (size cap; rate limit in Rack::Attack),
# AU-12.
class ExchangePushService
  PROTOCOL = "SPARC-PUSH-1"
  WINDOW = 5.minutes
  SIGNATURE_BYTES = 64

  # reason: what the audit log records; status: the HTTP status to answer.
  class Refused < StandardError
    attr_reader :reason, :status

    def initialize(reason, status: :unauthorized, message: "Push not accepted")
      @reason = reason
      @status = status
      super(message)
    end
  end

  def self.call(**) = new(**).call

  # The exact text a provider signs, for the push documentation and the
  # provider's own tooling.
  def self.signed_message(connection_id:, document_source_id:, timestamp:, body:)
    [ PROTOCOL, connection_id, document_source_id, timestamp, Digest::SHA256.hexdigest(body.to_s.b) ].join("\n")
  end

  def initialize(connection_id:, document_source_id:, body:, timestamp:, signature:, remote_ip:, content_type: nil)
    @connection_id = connection_id.to_s
    @source_id = document_source_id.to_s
    @body = body.to_s.b
    @timestamp = timestamp.to_s.strip
    @signature = signature.to_s.strip
    @remote_ip = remote_ip.to_s
    @content_type = content_type
  end

  def call
    connection, source = locate!
    check_address!(connection)
    check_body!
    signed_at = check_timestamp!
    key = verify_signature!(connection)
    receipt = record(connection, source, key, signed_at)
    ExchangePushConfirmJob.perform_later(receipt.id)
    receipt
  rescue Refused => e
    refuse_audit(e, connection)
    raise
  end

  private

  def locate!
    raise Refused, :unknown_connection unless @connection_id.match?(/\A\d+\z/) && @source_id.match?(/\A\d+\z/)

    connection = ExchangeConnection.find_by(id: @connection_id)
    raise Refused, :unknown_connection unless connection
    raise Refused, :push_not_enabled unless connection.push_enabled?

    source = connection.document_sources.find_by(id: @source_id)
    raise Refused, :unknown_document unless source&.enabled?

    [ connection, source ]
  end

  def check_address!(connection)
    return if connection.allowed_cidrs.empty?

    ip = IPAddr.new(@remote_ip)
    return if connection.allowed_cidrs.any? { |cidr| IPAddr.new(cidr).include?(ip) }

    raise Refused, :address_not_allowed
  rescue IPAddr::Error
    raise Refused, :address_not_allowed
  end

  def check_body!
    raise Refused.new(:empty, status: :bad_request, message: "The push carries no document") if @body.strip.empty?

    max = SparcConfig.max_upload_bytes
    return if @body.bytesize <= max

    raise Refused.new(:too_large, status: :content_too_large, message: "The document exceeds the #{max}-byte limit")
  end

  def check_timestamp!
    raise Refused, :bad_timestamp unless @timestamp.match?(/\A\d{1,12}\z/)

    signed_at = Time.at(@timestamp.to_i).utc
    raise Refused, :stale unless (Time.current - signed_at).abs <= WINDOW

    signed_at
  end

  # Strict base64 of exactly 64 bytes, verified against each pinned key.
  def verify_signature!(connection)
    raw = Base64.strict_decode64(@signature)
    raise Refused, :bad_signature unless raw.bytesize == SIGNATURE_BYTES

    message = self.class.signed_message(connection_id: connection.id, document_source_id: @source_id,
                                        timestamp: @timestamp, body: @body)
    key = connection.push_public_keys.find do |pinned|
      ExchangeConnection.ed25519_key(pinned)&.verify(nil, raw, message)
    rescue OpenSSL::PKey::PKeyError
      false
    end
    raise Refused, :bad_signature unless key

    @signature_sha256 = Digest::SHA256.hexdigest(raw)
    key
  rescue ArgumentError
    raise Refused, :bad_signature
  end

  def record(connection, source, key, signed_at)
    receipt = ExchangePushReceipt.transaction do
      ExchangePushReceipt.create!(
        exchange_connection: connection, exchange_document_source: source,
        sha256: Digest::SHA256.hexdigest(@body), byte_size: @body.bytesize, content_type: @content_type.presence,
        signature_sha256: @signature_sha256, key_fingerprint: ExchangeConnection.key_fingerprint(key),
        signed_at: signed_at, remote_ip: @remote_ip.presence, status: "pending"
      ).tap do |r|
        r.file.attach(io: StringIO.new(@body), filename: "push-#{r.id}", content_type: "application/octet-stream")
      end
    end
    connection.update_columns(last_pushed_at: Time.current, last_push_status: "pending", updated_at: Time.current)
    AuditEvent.log(action: "exchange_push_received", user: nil, subject: connection,
                   metadata: { push_receipt_id: receipt.id, document_source_id: source.id, sha256: receipt.sha256,
                               byte_size: receipt.byte_size, key: receipt.key_fingerprint, remote_ip: @remote_ip })
    receipt
  rescue ActiveRecord::RecordNotUnique
    raise replayed
  rescue ActiveRecord::RecordInvalid => e
    raise e unless e.record.errors.of_kind?(:signature_sha256, :taken)

    raise replayed
  end

  def replayed = Refused.new(:replayed, status: :conflict, message: "This signed request was already received")

  def refuse_audit(error, connection)
    AuditEvent.log(action: "exchange_push_refused", user: nil, subject: connection,
                   metadata: { reason: error.reason.to_s, connection_id: @connection_id.first(20),
                               document_source_id: @source_id.first(20), remote_ip: @remote_ip, byte_size: @body.bytesize })
  end
end
