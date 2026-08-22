# frozen_string_literal: true

# #832 — REST API for POA&M risks, nested on a POA&M document.
#
#   GET    /api/v1/poam_documents/:poam_document_id/risks
#   POST   /api/v1/poam_documents/:poam_document_id/risks
#   GET    /api/v1/poam_risks/:id
#   PATCH  /api/v1/poam_risks/:id
#   DELETE /api/v1/poam_risks/:id
#
# The reason this exists as an API surface rather than UI-only: a risk missing
# OSCAL-required content used to be accepted and only fail much later at export,
# with nothing to say which record was at fault. Rejecting it here returns a 422
# naming the missing fields, at the point of entry. Api::V1::BaseController maps
# ActiveRecord::RecordInvalid to that 422 already; `missing_fields` adds the
# machine-readable list so a client can highlight them without parsing prose.
#
# NIST 800-53 Controls:
#   IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC),
#   AU-12 (audit record generation), CA-5 (plan of action and milestones)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::PoamRisksController < Api::V1::BaseController
  before_action :set_document, only: %i[index create]
  before_action :set_risk,     only: %i[show update destroy]
  before_action :authorize_read!,  only: %i[index show]
  before_action :authorize_write!, only: %i[create update destroy]

  # GET /api/v1/poam_documents/:poam_document_id/risks
  def index
    result = paginate(@document.poam_risks.order(:id), items: 50)

    render json: {
      data: result[:data].map { |risk| serialize(risk) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/poam_risks/:id
  def show
    render json: { data: serialize(@risk, detailed: true) }
  end

  # POST /api/v1/poam_documents/:poam_document_id/risks
  def create
    risk = @document.poam_risks.new(risk_params)
    risk.uuid = SecureRandom.uuid if risk.uuid.blank?
    risk.save!

    audit_log("poam_risk_created", subject: risk,
              metadata: { poam_document_id: @document.id, uuid: risk.uuid })
    render json: { data: serialize(risk, detailed: true) }, status: :created
  end

  # PATCH /api/v1/poam_risks/:id
  def update
    @risk.update!(risk_params)

    audit_log("poam_risk_updated", subject: @risk,
              metadata: { poam_document_id: @risk.poam_document_id, uuid: @risk.uuid })
    render json: { data: serialize(@risk, detailed: true) }
  end

  # DELETE /api/v1/poam_risks/:id
  def destroy
    audit_log("poam_risk_deleted", subject: @risk,
              metadata: { poam_document_id: @risk.poam_document_id, uuid: @risk.uuid })
    @risk.destroy
    render json: { data: { id: @risk.id, uuid: @risk.uuid, deleted: true } }
  end

  private

  # #1010 — slug OR id. A POA&M document is slug-addressed everywhere else
  # (`GET /api/v1/poam_documents/:slug`), so a caller who lists documents and
  # then asks for their risks was handed a 404 for using the identifier the
  # listing gave them. Found while building the sibling sub-resources, which
  # accept both.
  def set_document
    param = params[:poam_document_id].to_s
    @document = PoamDocument.find_by(slug: param) || PoamDocument.find(param)
    @boundary = @document.authorization_boundary
  end

  def set_risk
    @risk = PoamRisk.find(params[:id])
    @document = @risk.poam_document
    @boundary = @document&.authorization_boundary
  end

  def risk_params
    permit_strictly(:poam_risk,
      :uuid, :title, :description, :statement, :status,
      :deadline, :likelihood, :impact, :remarks
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
      poam_document_id: risk.poam_document_id
    }

    # Surfaced on every response, not only on failure: a risk that predates the
    # #832 validations is already persisted and will reject the next save. A
    # client listing risks can show which ones need completing rather than
    # discovering it one failed edit at a time.
    missing = risk.missing_required_fields
    data[:missing_fields] = missing if missing.any?

    if detailed
      data[:description] = risk.description
      data[:statement] = risk.statement
      data[:remarks] = risk.remarks
      data[:created_at] = risk.created_at.iso8601
      data[:updated_at] = risk.updated_at.iso8601
    end

    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("poam.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view POA&M risks"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("poam.write", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to modify POA&M risks"
  end
end
