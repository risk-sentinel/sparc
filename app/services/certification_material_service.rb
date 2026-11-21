# frozen_string_literal: true

require "digest"
require "stringio"

# Receives one of the materials a Class A certification rests on (#1354,
# FedRAMP FRC-CLA-EAM): a SOC 2 Type II report, a bridge letter, a Readiness
# Assessment Report, a Security Assessment Plan, and the like.
#
# These are PDFs and other files FedRAMP publishes no schema for, so they are
# not schema-checked. Everything else is as for any received document: the
# exact bytes are kept once, by SHA-256, on the connection's boundary, and a
# reviewer of that boundary accepts or rejects each one
# (ReceivedDocumentReviewService, separation of duties included). Each kind
# of material is its own stream, so a new SOC 2 report, once accepted,
# supersedes the last one.
#
# Materials are never listed in the boundary's exchange index: they are the
# provider's, not the boundary's to serve on.
#
# NIST SP 800-53: CA-3, CA-6 (the evidence a Class A acceptance rests on),
# SA-9, SI-7 and AU-10 (bytes and SHA-256 fixed at receipt), AU-12.
class CertificationMaterialService
  class Error < StandardError; end

  Outcome = Struct.new(:document, :status, keyword_init: true) do
    def stored? = status == :stored
    def unchanged? = status == :unchanged
  end

  def self.call(**) = new(**).call

  def self.stream_key(connection, kind) = "class_a:connection:#{connection.id}:#{kind}"

  def initialize(connection:, kind:, bytes:, filename: nil, content_type: nil, received_by: nil)
    @connection = connection
    @kind = kind.to_s
    @bytes = bytes.to_s.b
    @filename = filename.to_s.presence
    @content_type = content_type.to_s.presence
    @received_by = received_by
  end

  def call
    check!
    sha256 = Digest::SHA256.hexdigest(@bytes)
    stream_key = self.class.stream_key(@connection, @kind)
    existing = ReceivedDocument.find_by(stream_key: stream_key, sha256: sha256)
    return Outcome.new(document: existing, status: :unchanged) if existing

    document = ReceivedDocument.transaction do
      ReceivedDocument.create!(
        authorization_boundary: @connection.authorization_boundary, exchange_connection: @connection,
        source: "upload", stream_key: stream_key, format: ReceivedDocument::MATERIAL_FORMAT, document_type: @kind,
        fedramp_id: @connection.fedramp_id, sha256: sha256, byte_size: @bytes.bytesize, filename: @filename,
        content_type: @content_type, state: "pending_review", valid_document: true,
        validation: { "valid" => true, "checked" => false, "errors" => [], "warnings" => [] },
        received_at: Time.current, received_by: @received_by
      ).tap do |doc|
        doc.file.attach(io: StringIO.new(@bytes), filename: @filename || "#{@kind}-#{sha256.first(12)}",
                        content_type: @content_type || "application/octet-stream")
      end
    end
    audit(document)
    Outcome.new(document: document, status: :stored)
  end

  private

  def check!
    raise Error, "Class A materials are recorded only for a Class A connection" unless @connection.class_a?
    raise Error, "Choose what kind of material this is" unless ExchangeConnection::CLASS_A_MATERIALS.key?(@kind)
    raise Error, "Empty file" if @bytes.empty?

    max = SparcConfig.max_upload_bytes
    raise Error, "The file exceeds the #{max}-byte upload limit" if @bytes.bytesize > max
  end

  def audit(document)
    AuditEvent.log(action: "certification_material_stored", user: @received_by, subject: document,
                   metadata: { authorization_boundary_id: document.authorization_boundary_id,
                               connection_id: @connection.id, kind: @kind, sha256: document.sha256,
                               byte_size: document.byte_size })
  end
end
