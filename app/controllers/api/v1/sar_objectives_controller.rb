# frozen_string_literal: true

# REST API for an assessment's 800-53A objectives, nested on a SAR document.
#
#   GET   /api/v1/sar_documents/:sar_document_id/objectives
#   PATCH /api/v1/sar_documents/:sar_document_id/objectives/:id
#
# Recording a determination was web-only, so an assessment run by a pipeline
# could not record per-objective results at all. Both surfaces call
# SarObjectiveDetermination, which keeps the control's risk (and so the
# POA&M) in step with a failure.
#
# NIST 800-53 Controls: CA-2 (control assessments), CA-5, AC-3/AC-6
# (boundary-scoped RBAC), AU-12.
class Api::V1::SarObjectivesController < Api::V1::BaseController
  before_action :set_document
  before_action :authorize_read!,  only: :index
  before_action :authorize_write!, only: :update

  # GET /api/v1/sar_documents/:sar_document_id/objectives
  def index
    scope = objectives.includes(:sar_control).order("sar_controls.row_order", :row_order)
    scope = scope.where(sar_controls: { control_id: params[:control_id] }) if params[:control_id].present?
    result = paginate(scope, items: 200)

    render json: { data: result[:data].map { |objective| serialize(objective) }, meta: result[:meta] }
  end

  # PATCH /api/v1/sar_documents/:sar_document_id/objectives/:id
  # :id is the record id or the OSCAL objective id (ac-1_obj.a-1).
  def update
    objective = find_objective
    attrs = permit_strictly(:sar_control_objective, :status, :assessor_name, :assessor_notes).to_h.symbolize_keys

    unless SarObjectiveDetermination.new(objective).record(**attrs)
      return render json: { error: objective.errors.full_messages.to_sentence }, status: :unprocessable_content
    end

    audit_log("sar_objective_updated", subject: @document,
              metadata: { objective_id: objective.objective_id, status: objective.status })
    render json: { data: serialize(objective.reload) }
  end

  private

  def objectives
    SarControlObjective.joins(:sar_control).where(sar_controls: { sar_document_id: @document.id })
  end

  def find_objective
    param = params[:id].to_s
    objectives.find_by(objective_id: param) || objectives.find(param)
  end

  # slug OR id, as the sibling SAR risks controller accepts (#1010).
  def set_document
    param = params[:sar_document_id].to_s
    @document = SarDocument.find_by(slug: param) || SarDocument.find(param)
    @boundary = @document.authorization_boundary
  end

  def serialize(objective)
    {
      id: objective.id,
      uuid: objective.uuid,
      control_id: objective.sar_control.control_id,
      objective_id: objective.objective_id,
      label: objective.label,
      prose: objective.prose,
      parent_objective_id: objective.parent_objective_id,
      determinable: objective.determinable?,
      status: objective.status,
      assessor_name: objective.assessor_name,
      assessor_notes: objective.assessor_notes,
      assessed_at: objective.assessed_at&.utc&.iso8601
    }
  end

  def authorize_read!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("sar.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view SAR objectives"
  end

  def authorize_write!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("sar.write", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to record SAR objective results"
  end
end
