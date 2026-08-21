# frozen_string_literal: true

# #447 — triage decision endpoints, nested on a scanner finding (one disposition
# per finding, keyed by boundary + control_id).
#
#   GET    /api/v1/scanner_findings/:scanner_finding_id/disposition
#   POST   /api/v1/scanner_findings/:scanner_finding_id/disposition   (create/update)
#   DELETE /api/v1/scanner_findings/:scanner_finding_id/disposition
#
# NIST 800-53: IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC),
# SI-2 (flaw remediation), AU-12 (audit), AU-10 (signature provenance).
class Api::V1::FindingDispositionsController < Api::V1::BaseController
  NOT_FOUND_BODY = { error: "Not found" }.freeze

  before_action :set_finding
  before_action :authorize_read!,    only: %i[show]
  before_action :authorize_write!,   only: %i[create destroy]
  before_action :authorize_approve!, only: %i[approve reject]

  # GET .../disposition
  def show
    disposition = current_disposition
    return render json: NOT_FOUND_BODY, status: :not_found if disposition.nil?

    render json: { data: serialize(disposition) }
  end

  # POST .../disposition
  def create
    subject = FindingDispositionService.resolve_subject(
      params[:linked_subject_type], params[:linked_subject_id]
    )
    disposition = FindingDispositionService.new(@finding).upsert(
      kind: params[:kind].to_s,
      reason: params[:reason].to_s,
      decided_by: actor,
      # #1034 — the identity separation of duties is enforced on. `decided_by`
      # above is a display name and cannot serve: two users can share one.
      decided_by_user: current_user,
      linked_subject: subject,
      expiration: params[:expiration].presence
    )
    audit_log("finding_disposition_set", subject: disposition,
              metadata: { control_id: disposition.control_id, kind: disposition.kind })
    render json: { data: serialize(disposition) }, status: :created
  rescue FindingDispositionService::DispositionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE .../disposition
  def destroy
    disposition = current_disposition
    return render json: NOT_FOUND_BODY, status: :not_found if disposition.nil?

    audit_log("finding_disposition_cleared", subject: disposition,
              metadata: { control_id: disposition.control_id, kind: disposition.kind })
    disposition.destroy
    render json: { data: { control_id: disposition.control_id, deleted: true } }
  end

  # POST .../disposition/approve  (#809)
  def approve
    disposition = current_disposition
    return render json: NOT_FOUND_BODY, status: :not_found if disposition.nil?

    FindingDispositionService.approve(disposition, approved_by: actor, approved_by_user: current_user)
    audit_log("finding_disposition_approved", subject: disposition,
              metadata: { control_id: disposition.control_id, kind: disposition.kind })
    render json: { data: serialize(disposition) }
  end

  # POST .../disposition/reject  (#809)
  def reject
    disposition = current_disposition
    return render json: NOT_FOUND_BODY, status: :not_found if disposition.nil?

    FindingDispositionService.reject(disposition, approved_by: actor, approved_by_user: current_user)
    audit_log("finding_disposition_rejected", subject: disposition,
              metadata: { control_id: disposition.control_id, kind: disposition.kind })
    render json: { data: serialize(disposition) }
  end

  # #1034 — an authorization outcome, so 403 rather than the 422 a
  # DispositionError gets. A caller who is simply the wrong person needs to know
  # that, not that their input was malformed.
  rescue_from FindingDispositionService::SeparationOfDutiesError do |e|
    render json: { error: e.message }, status: :forbidden
  end

  private

  def actor
    current_user&.display_name.presence || current_user&.email
  end

  def set_finding
    @finding = ScannerFinding.find_by!(uuid: params[:scanner_finding_id])
    @boundary = @finding.authorization_boundary
  end

  def current_disposition
    FindingDisposition.find_by(
      authorization_boundary_id: @boundary.id, control_id: @finding.control_id
    )
  end

  def serialize(disposition)
    {
      id: disposition.id,
      uuid: disposition.uuid,
      control_id: disposition.control_id,
      kind: disposition.kind,
      reason: disposition.reason,
      hdf_status: disposition.hdf_status,
      expiration: disposition.expiration&.utc&.iso8601,
      expired: disposition.expired?,
      linked_subject_type: disposition.linked_subject_type,
      linked_subject_id: disposition.linked_subject_id,
      signature_hash: disposition.signature_hash,
      decided_by: disposition.decided_by,
      decided_at: disposition.decided_at&.utc&.iso8601,
      approval_status: disposition.approval_status,
      approved_by: disposition.approved_by,
      approved_at: disposition.approved_at&.utc&.iso8601,
      valid_until: disposition.valid_until&.utc&.iso8601,
      applicable: disposition.applicable?,
      authorization_boundary_id: disposition.authorization_boundary_id
    }
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view dispositions"
  end

  # #809 (D5) — amendment approval is a distinct permission the Instance Admin
  # assigns to roles via RBAC. Until the Role-assignment UI ships, admins approve.
  def authorize_approve!
    return if current_user.admin?
    return if current_user.has_permission?("amendment.approve", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to approve amendments"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.write", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to set dispositions"
  end
end
