# frozen_string_literal: true

# #1354 — the documents a boundary received, pulled from a connection or
# uploaded, and the receiving boundary's review of each version.
#
#   GET  /api/v1/authorization_boundaries/:authorization_boundary_id/received_documents
#   POST /api/v1/authorization_boundaries/:authorization_boundary_id/received_documents        upload
#   GET  .../received_documents/:id
#   GET  .../received_documents/:id?compare=:other_id   with a comparison to any other version
#   GET  .../received_documents/:id/file      the exact bytes received
#   GET  .../received_documents/:id/review_export.json | .md   the review, to share out of band
#   POST .../received_documents/:id/accept
#   POST .../received_documents/:id/respond   ask the provider for information
#   POST .../received_documents/:id/reject
#
# #1390 part G (owner, 2026-11-23): respond and reject take `questions`, each
# tied to a place in the document ({ pointer, label, detail, before, after,
# question }); a version that failed validation may be responded to or
# rejected (never accepted); `compare` compares with any other version of the
# same document in the boundary, calculated on request and never stored; the
# review export is the record a reviewer sends to the provider until #1394.
#
# Permissions, on the boundary (or across the instance):
#   read (index, show, file, review_export)  evidence.read
#   upload (create)                 exchange.upload
#   accept / respond / reject       exchange.review
#
# Upload (multipart `file`, or the raw document as the body; optional
# `document_format` and `document_type`) goes through ReceivedDocumentService,
# the same path a pull takes: validate, store once, compare with the version
# in effect. A version that fails validation is STORED, with its errors, and
# answered 201 like any other (owner, 2026-11-20); it can never be accepted.
# Bytes the stream already holds answer 200 with `status: "unchanged"`. 422
# only when the document is empty, too large or not a format SPARC reads.
#
# Separation of duties (owner, 2026-11-20): the person who uploaded a version
# cannot decide it; the instance administrator is exempt
# (ReceivedDocumentReviewService). That refusal is 403, not 422: the caller is
# the wrong person, the request is not malformed.
#
# NIST SP 800-53: AC-3 / AC-6 (boundary-scoped permissions), AC-5 (separation
# of duties), CA-3 (information exchange), SI-10 (validated on receipt),
# AU-10 (bytes and SHA-256 fixed at receipt; downloads carry the SHA-256),
# AU-12 (uploads, decisions and downloads are audited — FedRAMP CDS-TRC-ACL).
class Api::V1::ReceivedDocumentsController < Api::V1::BaseController
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show file review_export]
  before_action :authorize_upload!, only: %i[create]
  before_action :authorize_review!, only: %i[accept respond reject]
  before_action :set_document, only: %i[show file accept respond reject review_export]

  # Rails tries handlers last-declared first, so the subclass comes second.
  rescue_from ReceivedDocumentReviewService::Error do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  rescue_from ReceivedDocumentReviewService::SeparationOfDutiesError do |e|
    render json: { error: e.message }, status: :forbidden
  end

  # GET .../received_documents?state=&document_format=&stream=&document_type=
  def index
    scope = @boundary.received_documents.includes(:received_by, :reviewed_by).recent
    scope = scope.where(state: params[:state].to_s.split(",")) if params[:state].present?
    scope = scope.where(format: params[:document_format]) if params[:document_format].present?
    scope = scope.where(document_type: params[:document_type]) if params[:document_type].present?
    scope = scope.where(stream_key: params[:stream]) if params[:stream].present?
    scope = scope.where(exchange_connection_id: params[:exchange_connection_id]) if params[:exchange_connection_id].present?
    result = paginate(scope)
    render json: { data: result[:data].map { |d| serialize(d) }, meta: result[:meta] }
  end

  # GET .../received_documents/:id
  def show
    data = serialize(@document, detailed: true)
    if params[:compare].present?
      other = @document.stream_versions.find_by(id: params[:compare])
      return render(json: { error: "No other version of this document with id #{params[:compare]} in this boundary" }, status: :not_found) unless other
      return render(json: { error: "Version #{other.id} failed validation and cannot be compared" }, status: :unprocessable_content) unless other.valid_document?

      data[:comparison] = comparison(ReceivedDocumentViewer.new(@document, compare_to: other))
    end
    render json: { data: data }
  end

  # GET .../received_documents/:id/review_export(.json|.md)
  def review_export
    export = ReceivedDocumentReviewExport.new(@document)
    audit_log("received_document_review_exported", subject: @document,
              metadata: { authorization_boundary_id: @boundary.id, sha256: @document.sha256, format: params[:format].presence || "json" })
    if params[:format] == "md"
      send_data export.to_markdown, filename: export.filename("md"), type: "text/markdown; charset=utf-8", disposition: "attachment"
    else
      render json: { data: export.as_json }
    end
  end

  # GET .../received_documents/:id/file
  def file
    bytes = @document.bytes
    return render(json: { error: "The stored bytes of this version are missing" }, status: :not_found) if bytes.nil?

    audit_log("received_document_downloaded", subject: @document,
              metadata: { authorization_boundary_id: @boundary.id, sha256: @document.sha256, state: @document.state })
    response.headers["X-Content-SHA256"] = @document.sha256
    send_data bytes, type: @document.content_type.presence || "application/octet-stream",
                     filename: @document.filename.presence || "received-document-#{@document.id}",
                     disposition: "attachment"
  end

  # POST .../received_documents
  def create
    raw, filename, content_type = payload
    if raw.blank?
      return render(json: { error: "No document supplied",
                            note: "Send a multipart `file` field or the raw document as the request body" },
                    status: :unprocessable_content)
    end
    declared = params[:document_format].presence
    if declared && !DocumentValidationService::FORMATS.include?(declared)
      return render(json: { error: "Unknown document_format '#{declared}'",
                            details: [ "Known: #{DocumentValidationService::FORMATS.join(', ')}" ] },
                    status: :unprocessable_content)
    end

    connection = nil
    if params[:exchange_connection_id].present?
      connection = @boundary.exchange_connections.find_by(id: params[:exchange_connection_id])
      unless connection
        return render(json: { error: "exchange_connection_id is not a connection of this boundary" },
                      status: :unprocessable_content)
      end
    end

    outcome = ReceivedDocumentService.call(boundary: @boundary, bytes: raw, source: "upload", filename: filename,
                                           content_type: content_type, received_by: current_user,
                                           connection: connection,
                                           format: declared, document_type: params[:document_type].presence)
    render json: { status: outcome.status.to_s, data: serialize(outcome.document, detailed: true) },
           status: outcome.stored? ? :created : :ok
  rescue ReceivedDocumentService::Error => e
    render json: { error: "The document could not be received", details: e.message }, status: :unprocessable_content
  end

  # POST .../received_documents/:id/accept   { note }
  def accept
    ReceivedDocumentReviewService.accept(@document, user: current_user, note: params[:note])
    render json: { data: serialize(@document.reload, detailed: true) }
  end

  # POST .../received_documents/:id/respond  { note, questions[] } (a note or at least one question)
  def respond
    ReceivedDocumentReviewService.respond(@document, user: current_user, note: params[:note], questions: params[:questions])
    render json: { data: serialize(@document.reload, detailed: true) }
  end

  # POST .../received_documents/:id/reject   { note, questions[] } (a note or at least one question)
  def reject
    ReceivedDocumentReviewService.reject(@document, user: current_user, note: params[:note], questions: params[:questions])
    render json: { data: serialize(@document.reload, detailed: true) }
  end

  private

  def set_boundary
    key = params[:authorization_boundary_id].to_s
    @boundary =
      if key.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      elsif key.match?(UUID_FORMAT)
        AuthorizationBoundary.find_by(uuid: key.downcase) || AuthorizationBoundary.find_by!(slug: key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  # Scoped to the boundary in the path, so a version of another boundary is a
  # 404 rather than a document the caller's permission here would reach.
  def set_document
    @document = @boundary.received_documents.find(params[:id])
  end

  def payload
    upload = params[:file]
    if upload.respond_to?(:read)
      [ upload.read, upload.try(:original_filename), upload.try(:content_type) ]
    else
      [ request.raw_post.presence, params[:filename].presence, request.content_type ]
    end
  end

  def base_path = "/api/v1/authorization_boundaries/#{@boundary.id}/received_documents"

  def person(user)
    user && { id: user.id, name: user.display_name.presence || user.email }
  end

  def serialize(doc, detailed: false)
    path = "#{base_path}/#{doc.id}"
    data = {
      id: doc.id,
      authorization_boundary_id: doc.authorization_boundary_id,
      exchange_connection_id: doc.exchange_connection_id,
      exchange_document_source_id: doc.exchange_document_source_id,
      source: doc.source,
      stream: doc.stream_key,
      format: doc.format,
      document_type: doc.document_type,
      fedramp_id: doc.fedramp_id,
      filename: doc.filename,
      content_type: doc.content_type,
      sha256: doc.sha256,
      byte_size: doc.byte_size,
      state: doc.state,
      valid: doc.valid_document,
      # #1354 — true: a push the fresh pull confirmed; false: pushed bytes it
      # did not (flagged, never auto-accepted); null: not from a push.
      push_confirmed: doc.push_confirmed,
      counts: { regression: doc.regression_count, improvement: doc.improvement_count, neutral: doc.neutral_count },
      received_at: doc.received_at&.utc&.iso8601,
      received_by: person(doc.received_by),
      review: {
        action: doc.review_action,
        note: doc.review_note,
        reviewed_at: doc.reviewed_at&.utc&.iso8601,
        reviewed_by: person(doc.reviewed_by),
        questions: doc.questions
      },
      compared_with_id: doc.compared_with_id,
      scan_run_id: doc.scan_run_id,
      links: { self: path, file: "#{path}/file" }
    }
    return data unless detailed

    data.merge(
      validation: {
        valid: doc.valid_document,
        schema: doc.validation["schema"],
        errors: doc.validation_errors,
        warnings: doc.validation_warnings,
        warnings_total: doc.validation["warnings_total"],
        # #1390 part G: each error with where it is, what is wrong and what
        # the provider needs to send.
        guidance: ValidationGuidance.new(doc).items.map(&:to_h)
      },
      delta: {
        first_version: doc.delta["first_version"],
        identical: doc.delta["identical"],
        truncated: doc.delta["truncated"],
        counts: doc.delta["counts"],
        changes: doc.delta_changes
      },
      in_effect_version_id: doc.in_effect? ? doc.id : doc.in_effect_version&.id,
      # Whether THIS caller may decide it: open, valid where accepting, and
      # not their own upload (AC-5).
      may_decide: doc.decidable? && ReceivedDocumentReviewService.may_decide?(doc, current_user),
      links: data[:links].merge(accept: "#{path}/accept", respond: "#{path}/respond", reject: "#{path}/reject",
                                review_export: "#{path}/review_export")
    )
  end

  # A comparison calculated on request (never stored), in the shape of the
  # stored delta.
  def comparison(viewer)
    { compared_with_id: viewer.compared.id, recorded: viewer.recorded?, truncated: viewer.truncated?,
      counts: viewer.counts,
      changes: viewer.changes.map { |c| { kind: c.kind, key: c.key, pointer: c.pointer, summary: c.summary, before: c.before, after: c.after } } }
  end

  def authorize_read!
    authorize_boundary!("evidence.read", "Not authorized to view this boundary's received documents")
  end

  def authorize_upload!
    authorize_boundary!("exchange.upload", "Not authorized to upload documents to this boundary")
  end

  def authorize_review!
    authorize_boundary!("exchange.review", "Not authorized to review this boundary's received documents")
  end

  def authorize_boundary!(key, message)
    return if current_user.instance_administrator?
    return if current_user.has_permission?(key, authorization_boundary_id: @boundary.id)

    raise NotAuthorizedError, message
  end
end
