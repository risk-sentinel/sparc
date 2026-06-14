# frozen_string_literal: true

# UI submit-for-review / approve / reject actions for trust-store documents
# (#630). Reuses the host controller's `publish_config` (from Publishable) for
# the document + redirect target, and routes every transition through
# DocumentApprovalService (the same code path the API uses).
#
# Including controllers must also include Publishable and run their set_* /
# write before_actions for these actions. Approver authority + separation of
# duties are enforced in the service.
module DocumentApprovalActions
  extend ActiveSupport::Concern

  # POST /<resource>/:id/submit_for_review
  def submit_for_review
    run_approval_transition { |svc| svc.submit_for_review! }
  end

  # POST /<resource>/:id/approve
  def approve
    run_approval_transition { |svc| svc.approve! }
  end

  # POST /<resource>/:id/reject
  def reject
    run_approval_transition { |svc| svc.reject!(reason: params[:reason]) }
  end

  private

  def run_approval_transition
    config = publish_config
    doc = config[:document]
    result = yield DocumentApprovalService.new(document: doc, actor: current_user)

    if result.success?
      flash[:success] = approval_flash_message(result.document, config[:label])
    else
      flash[:error] = result.error
    end
    redirect_to config[:redirect_path]
  end

  def approval_flash_message(doc, label)
    case doc.approval_status
    when "pending_review" then "#{label} submitted for review."
    when "approved"       then "#{label} approved."
    when "rejected"       then "#{label} rejected."
    else "#{label} approval updated."
    end
  end
end
