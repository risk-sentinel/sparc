# frozen_string_literal: true

require "stringio"

# A reviewer of the receiving boundary decides each received version (#1354):
#
#   accept  — the version takes effect for its stream; the one it replaces
#             becomes superseded. An HDF document also goes through the
#             existing ingest into the boundary's findings, exactly as an HDF
#             upload does.
#   respond — the reviewer asked the provider for information. The version
#             stays out of effect; the one in effect stays in effect.
#   reject  — on record, never in effect.
#
# Separation of duties (owner, 2026-11-20): the person who uploaded a version
# cannot accept, answer or reject it. The break-glass administrator is
# exempt, as for finding dispositions (FindingDispositionService.can_approve?).
# Pulled versions have no uploader.
#
# Authorization (exchange.review on the boundary) is the caller's; this
# enforces the rules of the decision itself.
#
# NIST SP 800-53: AC-5 (separation of duties), CA-3, CA-6 (acceptance of what
# a provider asserts), AU-10 and AU-12 (each decision audited, with who).
class ReceivedDocumentReviewService
  class Error < StandardError; end
  class SeparationOfDutiesError < Error; end

  AUDIT_ACTIONS = {
    "accept" => "received_document_accepted", "auto_accept" => "received_document_auto_accepted",
    "respond" => "received_document_responded", "reject" => "received_document_rejected"
  }.freeze

  def self.accept(document, user:, note: nil) = new(document, user).decide("accept", note)
  def self.respond(document, user:, note:) = new(document, user).decide("respond", note)
  def self.reject(document, user:, note:) = new(document, user).decide("reject", note)

  # A version with no changes or improvements only; no reviewer.
  def self.auto_accept(document) = new(document, nil).decide("auto_accept", nil)

  def self.may_decide?(document, user)
    return false unless user
    return true if user.admin?

    document.received_by_id.blank? || document.received_by_id != user.id
  end

  def initialize(document, user)
    @document = document
    @user = user
  end

  def decide(action, note)
    guard!(action, note)

    ReceivedDocument.transaction do
      @document.lock!
      raise Error, "This version was decided while you were looking at it" unless @document.open?

      case action
      when "accept", "auto_accept" then accept!
      when "respond" then @document.state = "responded"
      when "reject" then @document.state = "rejected"
      else raise Error, "Unknown decision #{action.inspect}"
      end
      @document.update!(review_action: action, review_note: note.presence, reviewed_at: Time.current,
                        reviewed_by: @user)
    end

    audit(action)
    @document
  end

  private

  def guard!(action, note)
    raise Error, "Only a version that passed validation can be accepted" if action.in?(%w[accept auto_accept]) && !@document.valid_document?
    raise Error, "This version is #{@document.state.humanize.downcase} and has been decided" unless @document.open?
    raise Error, "Say why, so the provider and the record have it" if action.in?(%w[respond reject]) && note.blank?
    return if action == "auto_accept"
    return if self.class.may_decide?(@document, @user)

    raise SeparationOfDutiesError, "A received document cannot be decided by the person who uploaded it"
  end

  def accept!
    ReceivedDocument.in_effect.where(stream_key: @document.stream_key).where.not(id: @document.id)
                    .update_all(state: "superseded", updated_at: Time.current)
    @document.state = "accepted"
    ingest_hdf if @document.format == "hdf"
  end

  # Owner, 2026-11-20: an accepted HDF document flows into the boundary's
  # findings, as an HDF upload does. A failed ingest fails the acceptance.
  def ingest_hdf
    run = HdfIngestService.new(@document.authorization_boundary).ingest(
      @document.bytes, source_filename: @document.filename.presence || "received.hdf.json",
                       created_by: @user ? (@user.display_name.presence || @user.email) : "auto-accepted (#{@document.source})",
                       scanner_scope: "boundary"
    )
    @document.scan_run = run
  rescue HdfIngestService::IngestError => e
    raise Error, "The HDF document could not be added to the boundary's findings: #{e.message}"
  end

  def audit(action)
    AuditEvent.log(action: AUDIT_ACTIONS.fetch(action), user: @user, subject: @document,
                   metadata: { authorization_boundary_id: @document.authorization_boundary_id, state: @document.state,
                               sha256: @document.sha256, regressions: @document.regression_count,
                               note: @document.review_note }.compact)
  end
end
