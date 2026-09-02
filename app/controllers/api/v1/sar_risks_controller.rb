# frozen_string_literal: true

# #1090 — REST API for SAR risks, nested on a SAR document.
#
#   GET    /api/v1/sar_documents/:sar_document_id/risks
#   POST   /api/v1/sar_documents/:sar_document_id/risks
#   GET    /api/v1/sar_risks/:id
#   PATCH  /api/v1/sar_risks/:id
#   DELETE /api/v1/sar_risks/:id
#
# WHY THIS EXISTS
#
# SAR risks had NO API at all. POA&M has eight sub-resource controllers; SAR had
# none, so its results, risks, findings and observations were reachable only
# through the HTML enrich form — which permitted exactly `title`, `description`
# and `status`. An operator could create a risk but could not say how bad it was,
# and no integrator could touch one.
#
# `impact` and `likelihood` are the OSCAL rating, carried out through
# `characterizations[].facets[]` (see RiskRating). Accepting them here is half of
# #1090; the other half is that the exporter now writes them.
#
# A risk belongs to a sar_result, not to the document directly, so `create`
# resolves the result: an explicit `sar_result_id` when given, otherwise the
# document's first. That mirrors what the enrich form does rather than inventing
# a second rule.
#
# NIST 800-53 Controls:
#   IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC),
#   AU-12 (audit record generation), CA-2 (control assessments)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::SarRisksController < Api::V1::BaseController
  include RiskCollectionParams

  before_action :set_document, only: %i[index create]
  before_action :set_risk,     only: %i[show update destroy]
  before_action :authorize_read!,  only: %i[index show]
  before_action :authorize_write!, only: %i[create update destroy]

  # GET /api/v1/sar_documents/:sar_document_id/risks
  def index
    scope = SarRisk.where(sar_result_id: @document.sar_results.select(:id)).order(:id)
    result = paginate(scope, items: 50)

    render json: { data: result[:data].map { |risk| serialize(risk) }, meta: result[:meta] }
  end

  # GET /api/v1/sar_risks/:id
  def show
    render json: { data: serialize(@risk, detailed: true) }
  end

  # POST /api/v1/sar_documents/:sar_document_id/risks
  def create
    result = resolve_result!
    risk = result.sar_risks.new(risk_params)
    risk.uuid = SecureRandom.uuid if risk.uuid.blank?
    risk.save!

    audit_log("sar_risk_created", subject: risk,
              metadata: { sar_document_id: @document.id, uuid: risk.uuid })
    render json: { data: serialize(risk, detailed: true) }, status: :created
  end

  # PATCH /api/v1/sar_risks/:id
  def update
    @risk.update!(risk_params)

    audit_log("sar_risk_updated", subject: @risk,
              metadata: { sar_document_id: @document&.id, uuid: @risk.uuid })
    render json: { data: serialize(@risk, detailed: true) }
  end

  # DELETE /api/v1/sar_risks/:id
  def destroy
    audit_log("sar_risk_deleted", subject: @risk,
              metadata: { sar_document_id: @document&.id, uuid: @risk.uuid })
    @risk.destroy
    render json: { data: { id: @risk.id, uuid: @risk.uuid, deleted: true } }
  end

  private

  # slug OR id, matching the sibling POA&M controllers — a caller who listed
  # documents gets the identifier the listing gave them, not a 404 (#1010).
  def set_document
    param = params[:sar_document_id].to_s
    @document = SarDocument.find_by(slug: param) || SarDocument.find(param)
    @boundary = @document.authorization_boundary
  end

  def set_risk
    @risk = SarRisk.find(params[:id])
    @document = @risk.sar_result&.sar_document
    @boundary = @document&.authorization_boundary
  end

  def resolve_result!
    requested = params.dig(:sar_risk, :sar_result_id).presence
    if requested
      @document.sar_results.find(requested)
    else
      @document.sar_results.order(:id).first ||
        raise(ActiveRecord::RecordNotFound, "this SAR has no result to attach a risk to")
    end
  end

  # #1092 — the OSCAL collections are permitted here as SHAPES, not blobs; see
  # RiskCollectionParams. `remediations_data` is SAR-only: POA&M models responses
  # as real `poam_remediations` rows with their own controller.
  def risk_params
    permit_strictly(:sar_risk,
      :uuid, :title, :description, :statement, :status,
      :deadline, :likelihood, :impact, :remarks,
      **risk_collection_filters,
      remediations_data: RiskCollectionParams::REMEDIATIONS
    )
  end

  def serialize(risk, detailed: false)
    data = {
      id: risk.id,
      uuid: risk.uuid,
      title: risk.title,
      status: risk.status,
      deadline: risk.deadline&.utc&.iso8601,
      likelihood: risk.likelihood,
      impact: risk.impact,
      sar_result_id: risk.sar_result_id
    }

    # Reported on every response, as on POA&M risks: a risk that predates the
    # #1090 validations is already persisted and will reject its next save. A
    # client can show what needs completing instead of discovering it one failed
    # edit at a time.
    missing = risk.missing_required_fields
    data[:missing_fields] = missing if missing.any?

    if detailed
      data[:description] = risk.description
      data[:statement] = risk.statement
      data[:remarks] = risk.remarks
      # #1092 — round-trip visibility: a client that can WRITE these must be
      # able to read back what it wrote, and an integrator needs to see what
      # arrived on import before deciding what to amend.
      data[:threat_ids] = risk.threat_ids_data
      data[:mitigating_factors] = risk.mitigating_factors_data
      data[:origins] = risk.origins_data
      data[:risk_log] = risk.risk_log_data
      data[:remediations] = risk.remediations_data
      # The rating as it will actually be EXPORTED, so a client can see the
      # facets rather than infer them from impact/likelihood.
      data[:characterizations] = risk.characterizations_for_export
      data[:created_at] = risk.created_at.iso8601
      data[:updated_at] = risk.updated_at.iso8601
    end

    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("sar.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view SAR risks"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("sar.write", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to modify SAR risks"
  end
end
