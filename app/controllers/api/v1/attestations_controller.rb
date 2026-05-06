# REST API for evidence attestations.
#
# Attestations are periodic-review records signed off by reviewers
# (control owner / system owner / ISSO / CISO / assessor / AO) that an
# evidence artifact accurately represents the current state of one or
# more linked controls. Each attestation carries a tamper-evident
# SHA-256 signature_hash for non-repudiation.
#
# This controller fills the API gap left by the existing UI-only
# `AttestationsController` (per the SPARC api-first rule) and adds the
# CMS / SAF CLI attestation export endpoint introduced in #440 that
# emits records in the canonical schema consumed by SAF CLI, Heimdall,
# and OSCAL emitters.
#
# Endpoints:
#   GET    /api/v1/evidences/:evidence_id/attestations          — list (paginated)
#   GET    /api/v1/evidences/:evidence_id/attestations/:id      — show
#   POST   /api/v1/evidences/:evidence_id/attestations          — create + sign
#   DELETE /api/v1/evidences/:evidence_id/attestations/:id      — delete (audit-logged)
#   GET    /api/v1/evidences/:evidence_id/attestations/export   — CMS-shape JSON export
#                                                                  (denormalized one record per linked control_id)
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (evidence.read / evidence.write RBAC)
#   AU-12 Audit Record Generation (mutations logged)
#   CA-7 Continuous Monitoring (periodic re-attestation cadence captured via `frequency`)
#   CA-2 Security Assessment (attestation as assessment evidence)
#
class Api::V1::AttestationsController < Api::V1::BaseController
  before_action :set_evidence
  before_action :set_attestation, only: %i[show destroy]
  before_action :authorize_read!, only: %i[index show export]
  before_action :authorize_write!, only: %i[create destroy]

  # GET /api/v1/evidences/:evidence_id/attestations
  def index
    scope = @evidence.attestations.order(attested_at: :desc)
    result = paginate(scope)
    result[:data] = result[:data].map { |a| serialize(a) }
    render json: result
  end

  # GET /api/v1/evidences/:evidence_id/attestations/:id
  def show
    render json: { data: serialize(@attestation, detailed: true) }
  end

  # POST /api/v1/evidences/:evidence_id/attestations
  def create
    attestation = @evidence.attestations.build(attestation_params)

    if attestation.save
      attestation.generate_signature!
      @evidence.update!(status: :attested) unless @evidence.attested?
      audit_log("attestation_created", subject: attestation, metadata: { evidence_id: @evidence.id })
      render json: { data: serialize(attestation, detailed: true) }, status: :created
    else
      render json: { error: "Validation failed", details: attestation.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/evidences/:evidence_id/attestations/:id
  def destroy
    audit_log("attestation_deleted", subject: @attestation, metadata: { evidence_id: @evidence.id })
    @attestation.destroy
    head :no_content
  end

  # GET /api/v1/evidences/:evidence_id/attestations/export
  #
  # Emits CMS / SAF CLI attestation JSON for all attestations on this
  # evidence, denormalized one record per linked control_id (per the
  # canonical schema). Returns an empty array if the evidence has no
  # control links — the CMS shape is meaningless without a control_id.
  def export
    records = CmsAttestationExportService.new(@evidence.attestations).call
    render json: { data: records, meta: { count: records.length, schema: "cms-attestation-v1" } }
  end

  private

  # Accept either numeric id or slug — the UI route uses slug; API
  # callers commonly use numeric id.
  def set_evidence
    key = params[:evidence_id]
    @evidence =
      if key.to_s.match?(/\A\d+\z/)
        Evidence.find(key)
      else
        Evidence.find_by!(slug: key)
      end
  end

  def set_attestation
    @attestation = @evidence.attestations.find(params[:id])
  end

  def attestation_params
    params.require(:attestation).permit(
      :attester_name, :attester_email, :role, :statement, :attested_at,
      :frequency, :status
    )
  end

  def serialize(attestation, detailed: false)
    data = {
      id: attestation.id,
      evidence_id: attestation.evidence_id,
      attester_name: attestation.attester_name,
      role: attestation.role,
      role_label: attestation.role_label,
      attested_at: attestation.attested_at.utc.iso8601,
      frequency: attestation.frequency,
      status: attestation.status,
      created_at: attestation.created_at.utc.iso8601
    }

    if detailed
      data[:attester_email] = attestation.attester_email
      data[:statement] = attestation.statement
      data[:signature_hash] = attestation.signature_hash
      data[:frequency_label] = attestation.frequency_label
    end

    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read")

    raise NotAuthorizedError, "Not authorized to view attestations"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.write")

    raise NotAuthorizedError, "Not authorized to manage attestations"
  end
end
