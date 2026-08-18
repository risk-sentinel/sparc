# REST API for evidence attestations.
#
# Attestations are periodic-review records signed off by an accountable
# reviewer, asserting that an evidence artifact accurately represents the
# current state of one or more linked controls. Each carries a tamper-evident
# SHA-256 signature_hash for non-repudiation.
#
# #947 — who may attest is no longer a hardcoded list of role names. The
# attester resolves to a SPARC account, and the role they claim is checked
# against what they actually hold on the evidence's boundary, via the
# `evidence.attest` permission. Which roles carry it is instance configuration,
# so organizations with different rule sets express their own.
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
      # #947 — check the STATUS, not `attested?`.
      #
      # `Evidence#attested?` is explicitly defined as `attestations.any?`, which
      # SHADOWS the predicate the `status` enum generates for the "attested"
      # value. By the time this line runs the attestation has just been saved, so
      # the shadowing method is always true and the status update never fired —
      # evidence could be signed off and still read "Draft" everywhere. The old
      # spec asserted the status was one of four values, which no outcome could
      # fail, so nothing caught it.
      @evidence.update!(status: :attested) unless @evidence.status == "attested"
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

  # #947 — `attester_name` / `attester_email` are NOT permitted. They are the
  # snapshot the model takes from the resolved account (#934 rule), not values a
  # caller supplies. Permitting them would let a request name one person while
  # referencing another, which is precisely the unverifiable claim this issue
  # exists to close.
  def attestation_params
    params.require(:attestation).permit(
      :attester_user_id, :role, :statement, :attested_at,
      :frequency, :status
    )
  end

  def serialize(attestation, detailed: false)
    data = {
      id: attestation.id,
      evidence_id: attestation.evidence_id,
      attester_name: attestation.attester_name,
      attester_user_id: attestation.attester_user_id,
      # #947 — whether the recorded role was checkable against the roster.
      # False for rows written before the rule; those are reported, not
      # rewritten, so a consumer can tell a verified claim from a legacy one.
      attester_verified: attestation.attester_verified?,
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

  # #947 — scoped to the evidence's boundary, reconciling this controller with
  # the stricter web guard its sibling already carried a note about.
  #
  # The unscoped form was not merely laxer, it was WRONG IN BOTH DIRECTIONS:
  # `has_permission?(key)` with no boundary matches ONLY instance-scoped roles,
  # so a boundary-scoped ISSO holding `evidence.read` on the very boundary the
  # evidence belongs to was REFUSED here while being allowed in the UI, and an
  # instance-level grant passed for every boundary at once. Passing the boundary
  # is what makes the two surfaces answer the same question.
  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read",
                                           authorization_boundary_id: @evidence&.authorization_boundary_id)

    raise NotAuthorizedError, "Not authorized to view attestations"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.write",
                                           authorization_boundary_id: @evidence&.authorization_boundary_id)

    raise NotAuthorizedError, "Not authorized to manage attestations"
  end
end
