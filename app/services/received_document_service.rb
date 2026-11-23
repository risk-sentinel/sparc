# frozen_string_literal: true

require "digest"
require "stringio"

# Receives one document into a boundary (#1354): from a pull, or from a
# person's upload. Every arrival goes the same way:
#
#   1. validate (DocumentValidationService: schema and completeness);
#   2. store the exact bytes, once — a version whose SHA-256 its stream
#      already holds is not stored again;
#   3. compare it with the version in effect for its stream (ExchangeDelta);
#   4. every valid version that differs from what the stream holds waits for
#      a reviewer, an improvement included; an invalid one is stored with its
#      errors and never takes effect. Owner, 2026-11-20: only a byte-identical
#      re-delivery needs no person, and step 2 already records that as
#      unchanged, leaving the accepted version in effect.
#
# NIST SP 800-53: CA-3, SI-10, SI-7 and AU-10 (bytes and SHA-256 fixed at
# receipt), AU-12, CA-7.
class ReceivedDocumentService
  class Error < StandardError; end

  Outcome = Struct.new(:document, :status, keyword_init: true) do
    def stored? = status == :stored
    def unchanged? = status == :unchanged
  end

  def self.call(**) = new(**).call

  # @param source [String] "pull", "upload" or "push"
  # @param format [String, nil] the format the caller declares (a pull's
  #   document source names one); detected when nil
  # @param push_confirmed [Boolean, nil] false for pushed bytes the fresh
  #   pull did not confirm (ExchangePushConfirmService): flagged, and never
  #   auto-accepted
  def initialize(boundary:, bytes:, source:, filename: nil, content_type: nil, connection: nil,
                 document_source: nil, received_by: nil, format: nil, document_type: nil, push_confirmed: nil)
    @boundary = boundary
    @bytes = bytes.to_s.b
    @source = source.to_s
    @filename = filename
    @content_type = content_type
    @connection = connection || document_source&.exchange_connection
    @document_source = document_source
    @received_by = received_by
    @format = format.presence
    @document_type = document_type.presence
    @push_confirmed = push_confirmed
  end

  def call
    check_bytes!
    sha256 = Digest::SHA256.hexdigest(@bytes)
    validation = validate
    format = validation[:format] || @format
    raise Error, "Not a FedRAMP, OSCAL, HDF or XCCDF document SPARC can read: #{validation[:error]}" if format.blank?

    document_type = validation[:document_type] || @document_type
    stream_key = stream_key_for(format, document_type, validation)

    existing = ReceivedDocument.find_by(stream_key: stream_key, sha256: sha256)
    return Outcome.new(document: existing, status: :unchanged) if existing

    in_effect = ReceivedDocument.in_effect.find_by(stream_key: stream_key)
    delta = validation[:valid] ? compare(format, document_type, in_effect) : nil
    document = store(format: format, document_type: document_type, stream_key: stream_key,
                     sha256: sha256, validation: validation, delta: delta,
                     compared_with: delta && !delta.first_version? ? in_effect : nil)

    audit("received_document_stored", document)
    ReceivedDocumentReviewService.auto_accept(document) if delta&.auto_acceptable? && @push_confirmed != false
    Outcome.new(document: document.reload, status: :stored)
  end

  private

  def check_bytes!
    raise Error, "Empty document" if @bytes.strip.empty?
    # Class A materials are received by CertificationMaterialService, never
    # as a schema-checked document.
    raise Error, "Class A materials are added on the connection" if @format == ReceivedDocument::MATERIAL_FORMAT

    max = SparcConfig.max_upload_bytes
    raise Error, "Document exceeds the #{max}-byte upload limit" if @bytes.bytesize > max
  end

  # compared_with (#1390 part G): the version the recorded comparison was made
  # against, so the viewer can show both side by side.
  def store(format:, document_type:, stream_key:, sha256:, validation:, delta:, compared_with: nil)
    ReceivedDocument.transaction do
      doc = ReceivedDocument.create!(
        authorization_boundary: @boundary, exchange_connection: @connection,
        exchange_document_source: @document_source, source: @source, stream_key: stream_key,
        format: format, document_type: document_type, fedramp_id: fedramp_id(validation),
        sha256: sha256, byte_size: @bytes.bytesize, filename: @filename, content_type: @content_type,
        state: validation[:valid] ? "pending_review" : "invalid", valid_document: validation[:valid],
        validation: validation[:json], received_at: Time.current, received_by: @received_by,
        push_confirmed: @push_confirmed, compared_with: compared_with, **delta_attributes(delta)
      )
      doc.file.attach(io: StringIO.new(@bytes), filename: @filename.presence || "#{format}-document",
                      content_type: @content_type.presence || "application/octet-stream")
      doc
    end
  end

  def delta_attributes(delta)
    return { delta: {}, regression_count: 0, improvement_count: 0, neutral_count: 0 } unless delta

    { delta: delta_json(delta), regression_count: delta.counts[:regression].to_i,
      improvement_count: delta.counts[:improvement].to_i, neutral_count: delta.counts[:neutral].to_i }
  end

  # Validation never raises here: a document SPARC could not check is still
  # stored, with the reason as its error (owner, 2026-11-20).
  def validate
    result = DocumentValidationService.call(@bytes, filename: @filename, format: @format,
                                                    document_type: @document_type)
    { valid: result.valid?, format: result.format, document_type: result.document_type, json: result.as_json.deep_stringify_keys }
  rescue DocumentValidationService::Error, FedrampPackageSchemas::Error => e
    { valid: false, format: @format, document_type: @document_type, error: e.message,
      json: { "valid" => false, "errors" => [ { "check" => "readable", "pointer" => "", "message" => e.message } ],
              "warnings" => [] } }
  end

  def compare(format, document_type, in_effect)
    ExchangeDelta.compare(format: format, document_type: document_type,
                          before: in_effect&.bytes, after: @bytes)
  end

  def delta_json(delta)
    json = delta.respond_to?(:as_json) ? delta.as_json : delta.to_h
    json.deep_stringify_keys
  end

  # A pull's stream is its document address. An upload's is the boundary's
  # uploads of one format, document type and FedRAMP ID.
  # A pull's stream is its document address. An upload's (owner, 2026-11-20):
  # the provider the uploader picked (a connection of this boundary), or
  # else the identity the document carries — a package overview's FedRAMP
  # package ID, a report's package-overview address — so two providers'
  # uploads of one document type never replace each other.
  def stream_key_for(format, document_type, validation)
    return @document_source.stream_key if @document_source

    base = [ "upload", format, document_type.presence || "-" ]
    return [ *base, "connection:#{@connection.id}" ].join(":") if @connection

    [ *base, "boundary:#{@boundary.id}", "id:#{document_identity(validation) || '-'}" ].join(":")
  end

  # The package a FedRAMP document belongs to, read defensively: a document
  # that failed validation may be any JSON value.
  def document_identity(validation)
    return nil unless (validation[:format] || @format) == "fedramp"

    data = JSON.parse(@bytes)
    return nil unless data.is_a?(Hash)

    identification = data["serviceIdentification"]
    package_id = identification["fedRampPackageId"] if identification.is_a?(Hash)
    overview = data["certificationPackageOverviewUri"]
    value = (package_id.strip.presence if package_id.is_a?(String)) || (overview.strip.presence if overview.is_a?(String))
    value&.slice(0, 500)
  rescue JSON::ParserError
    nil
  end

  def fedramp_id(validation)
    @connection&.fedramp_id.presence || begin
      return nil unless validation[:format] == "fedramp"

      # A document that failed validation may be any JSON value, so each level
      # is checked before it is read.
      data = JSON.parse(@bytes)
      identification = data["serviceIdentification"] if data.is_a?(Hash)
      package_id = identification["fedRampPackageId"] if identification.is_a?(Hash)
      package_id.is_a?(String) ? package_id.strip.presence : nil
    rescue JSON::ParserError
      nil
    end
  end

  def audit(action, document)
    AuditEvent.log(action: action, user: @received_by, subject: document,
                   metadata: { authorization_boundary_id: @boundary.id, source: @source, format: document.format,
                               document_type: document.document_type, sha256: document.sha256,
                               state: document.state, connection_id: @connection&.id }.compact)
  end
end
