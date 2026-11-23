# frozen_string_literal: true

# #1354 — a boundary's received documents: FedRAMP, OSCAL, HDF and XCCDF
# versions pulled from a connection or uploaded by a person, and their review.
# A thin web client over the services the API
# (Api::V1::ReceivedDocumentsController) uses:
#
#   GET  /authorization_boundaries/:id/received_documents            — versions, by stream
#   POST /authorization_boundaries/:id/received_documents            — upload (ReceivedDocumentService)
#   GET  /authorization_boundaries/:id/received_documents/:id        — one version, its errors and delta
#   GET  /authorization_boundaries/:id/received_documents/:id/file   — the stored bytes
#   GET  .../:id/review_export.md | .json                            — the review, to share out of band
#   POST .../accept | respond | reject                               — ReceivedDocumentReviewService
#
# #1390 part G (owner, 2026-11-23): the version page is a document viewer
# (ReceivedDocumentViewer): change list (default when there is a compared
# version), side by side, this version, and the compared version, with
# "Compare with" any other version of the same document in this boundary.
# Questions asked about any place in the document go with Respond or Reject
# and are exported (Markdown, JSON) to send to the provider out of band.
#
# Owner, 2026-11-20: received documents and their reviews live in the
# boundary's evidence area; a document belongs to the boundary only once the
# boundary accepts it; a document that fails validation is stored with its
# errors, shown; the person who uploaded a version cannot decide it
# (the break-glass administrator is exempt, as for dispositions). Only a
# byte-identical re-delivery skips review, and that is not stored again.
#
# NIST SP 800-53: AC-3 (evidence.read / exchange.upload / exchange.review on
# the boundary), AC-5 (separation of duties, enforced in the review service
# and mirrored here so the controls are not offered), CA-3 (information
# exchange), SI-10 (validation shown), AU-12 (every decision audited).
class ReceivedDocumentsController < ApplicationController
  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show file review_export]
  before_action :authorize_upload!, only: %i[create]
  before_action :authorize_review!, only: %i[accept respond reject]
  before_action :set_document, only: %i[show file accept respond reject review_export]

  VIEWER_TABS = %w[changes side current compared].freeze

  def index
    documents = @boundary.received_documents.includes(:exchange_connection, :received_by).recent.to_a
    # One group per stream, the stream with the newest arrival first; inside a
    # stream, newest version first (documents are already in that order).
    @streams = documents.group_by(&:stream_key).values
    @can_upload = permission?("exchange.upload")
    @formats = DocumentValidationService::FORMATS
    @fedramp_document_types = fedramp_document_types
    @connections = @boundary.exchange_connections.order(:name)
  end

  def show
    @history = AuditEvent.for_subject(@document).includes(:user).order(:created_at)
    @in_effect = @document.in_effect_version
    @can_review = permission?("exchange.review")
    @may_decide = @can_review && @document.decidable? && may_decide?(@document)
    @uploader_blocked = @can_review && @document.decidable? && !may_decide?(@document)
    @viewer = ReceivedDocumentViewer.new(@document, compare_to: compare_version)
    @guidance = ValidationGuidance.new(@document).items
    @tab = viewer_tab
    @changed_only = params[:changed] != "0"
  end

  # The review as Markdown (to read and send) or JSON (for a system), to share
  # with the provider out of band until #1394 sends it.
  def review_export
    export = ReceivedDocumentReviewExport.new(@document)
    AuditEvent.log(action: "received_document_review_exported", user: current_user, subject: @document,
                   metadata: { authorization_boundary_id: @boundary.id, sha256: @document.sha256, format: request.format.symbol.to_s })
    respond_to do |format|
      format.md { send_data export.to_markdown, filename: export.filename("md"), type: "text/markdown; charset=utf-8", disposition: "attachment" }
      format.json { send_data JSON.pretty_generate(export.as_json), filename: export.filename("json"), type: "application/json", disposition: "attachment" }
    end
  end

  def create
    file = params[:file]
    return redirect_to(index_path, error: "Choose a document to upload.") if file.blank?

    connection = upload_connection
    return redirect_to(index_path, error: "That provider is not a connection of this boundary.") if connection == false

    outcome = ReceivedDocumentService.call(
      boundary: @boundary, bytes: file.read, source: "upload", filename: file.original_filename,
      content_type: file.content_type, received_by: current_user, connection: connection,
      format: params[:document_format].presence, document_type: params[:document_type].presence
    )
    redirect_to document_path(outcome.document), **upload_flash(outcome)
  rescue ReceivedDocumentService::Error => e
    redirect_to index_path, error: "Not received: #{e.message}"
  end

  # The stored bytes, exactly as received. Always an attachment, never
  # rendered inline (#894).
  def file
    bytes = @document.bytes
    return redirect_to(document_path(@document), error: "This version's file is missing.") if bytes.nil?

    send_data bytes, filename: @document.filename.presence || "#{@document.format}-#{@document.sha256.first(12)}",
                     type: download_type(bytes), disposition: "attachment"
  end

  def accept = decide(:accept, "Accepted. This version is now in effect for the boundary.")
  def respond = decide(:respond, "Response recorded. The version stays pending; the one in effect stays in effect.")
  def reject = decide(:reject, "Rejected. The version stays on record and never takes effect.")

  private

  # Owner, 2026-11-20: an upload may name its provider, one of this
  # boundary's connections, so it joins that provider's stream. nil when
  # none is named; false when the id names no connection of this boundary.
  def upload_connection
    id = params[:exchange_connection_id].presence
    return nil unless id

    @boundary.exchange_connections.find_by(id: id) || false
  end

  def decide(action, message)
    note = params[:note].to_s.strip
    options = action == :accept ? {} : { questions: params[:questions] }
    ReceivedDocumentReviewService.public_send(action, @document, user: current_user, note: note, **options)
    redirect_to document_path(@document), success: message
  rescue ReceivedDocumentReviewService::SeparationOfDutiesError => e
    redirect_to document_path(@document), error: e.message
  rescue ReceivedDocumentReviewService::Error => e
    redirect_to document_path(@document), error: "Not #{action == :accept ? 'accepted' : "#{action}ed"}: #{e.message}"
  end

  # Another version of the same document in this boundary, by id; nil for the
  # recorded comparison. The viewer refuses anything outside the stream.
  def compare_version
    id = params[:compare].presence
    id && @document.stream_versions.find_by(id: id)
  end

  def viewer_tab
    tab = params[:tab].presence
    return tab if VIEWER_TABS.include?(tab) && (tab == "current" || @viewer.compared?)

    @viewer.compared? ? "changes" : "current"
  end

  def set_boundary
    key = params[:authorization_boundary_id]
    @boundary =
      if key.to_s.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  # Scoped to the boundary in the URL, so a version of another boundary is
  # not found here whatever its id.
  def set_document
    @document = @boundary.received_documents.find(params[:id])
  end

  def authorize_read!
    authorize_permission!("evidence.read", authorization_boundary_id: @boundary.id)
  end

  def authorize_upload!
    authorize_permission!("exchange.upload", authorization_boundary_id: @boundary.id)
  end

  def authorize_review!
    authorize_permission!("exchange.review", authorization_boundary_id: @boundary.id)
  end

  def permission?(key)
    !SparcConfig.any_auth_enabled? || current_user&.has_permission?(key, authorization_boundary_id: @boundary.id) || false
  end

  # AC-5: the same rule the review service enforces. With sign-in off there is
  # no person to separate, so the controls are offered.
  def may_decide?(document)
    return true unless SparcConfig.any_auth_enabled?

    ReceivedDocumentReviewService.may_decide?(document, current_user)
  end

  def index_path = authorization_boundary_received_documents_path(@boundary)
  def document_path(document) = authorization_boundary_received_document_path(@boundary, document)

  def upload_flash(outcome)
    doc = outcome.document
    if outcome.unchanged?
      { warning: "Unchanged: this exact document (SHA-256 #{doc.sha256.first(12)}…) is already on record. Nothing new was stored." }
    elsif doc.state == "invalid"
      { error: "Stored, but it failed validation (#{doc.validation_errors.size} errors). It cannot be accepted; the errors are below." }
    else
      { success: "Received. The version is #{doc.state.humanize.downcase}." }
    end
  end

  # A Class A material is whatever file the provider supplied (a PDF, most
  # often); every other version is JSON or XML.
  def download_type(bytes)
    return @document.content_type.presence || "application/octet-stream" if @document.certification_material?

    bytes.lstrip.start_with?("<") ? "application/xml" : "application/json"
  end

  def fedramp_document_types
    FedrampPackageSchemas.document_types.sort
  rescue StandardError => e
    Rails.logger.warn("[ReceivedDocuments] FedRAMP document types unavailable: #{e.message}")
    []
  end
end
