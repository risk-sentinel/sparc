# frozen_string_literal: true

# API submit-for-review / approve / reject for trust-store documents (#630).
# Same DocumentApprovalService code path as the UI; renders a uniform JSON
# approval payload. Including controllers define `approval_document` and run
# their set_* (and, for submit, write-authorization) before_actions.
module DocumentApprovalApi
  extend ActiveSupport::Concern

  # POST /api/v1/<resource>/:id/submit_for_review
  def submit_for_review
    render_approval_result { |svc| svc.submit_for_review! }
  end

  # POST /api/v1/<resource>/:id/approve
  def approve
    render_approval_result { |svc| svc.approve! }
  end

  # POST /api/v1/<resource>/:id/reject
  def reject
    render_approval_result { |svc| svc.reject!(reason: params[:reason]) }
  end

  private

  def render_approval_result
    result = yield DocumentApprovalService.new(document: approval_document, actor: current_user)
    if result.success?
      render json: { data: serialize_approval(result.document) }
    else
      render json: { error: result.error }, status: (result.status_code || :unprocessable_entity)
    end
  end

  def serialize_approval(doc)
    {
      id:                   doc.id,
      slug:                 doc.try(:slug),
      name:                 doc.try(:name),
      approval_status:      doc.approval_status,
      submitted_by_user_id: doc.submitted_by_user_id,
      submitted_at:         doc.submitted_at&.iso8601,
      approved_by_user_id:  doc.approved_by_user_id,
      approved_at:          doc.approved_at&.iso8601,
      rejection_reason:     doc.rejection_reason
    }
  end
end
