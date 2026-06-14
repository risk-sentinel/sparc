# frozen_string_literal: true

# Review/approval workflow for trust-store documents (#630): Control Catalog,
# Profile, Baseline (a ProfileDocument facet), and CDEF.
#
#   draft → pending_review → approved → (publishable)
#                         ↘ rejected
#
# Single code path for the API and the UI (mirrors BackMatterResourcePromotionService,
# #372). The Approvable concern holds the state mutation; this service holds
# authority, self-approval (separation-of-duties) enforcement, content gating,
# and audit logging.
#
# Approvers (NIST AC-3 / AC-6):
#   - Instance admin, OR
#   - the per-type approve permission (catalogs.approve / profiles.approve / cdef.approve), OR
#   - the instance-scoped policy_manager role.
# Separation of duties: the submitter may NOT approve their own document
# (admin override only).
#
# NIST 800-53: CA-6 (Authorization), SA-10 (Developer Config Management),
# AC-3/AC-6 (approver authority), AU-2/AU-3 (audited transitions). Aligns with
# RMF SP 800-37 Task S-6 (Plan Review & Approval).
class DocumentApprovalService
  Result = Struct.new(:success, :document, :error, :status_code, keyword_init: true) do
    def success? = success
  end

  APPROVE_PERMISSION = {
    "ControlCatalog"  => "catalogs.approve",
    "ProfileDocument" => "profiles.approve",
    "CdefDocument"    => "cdef.approve"
  }.freeze

  def initialize(document:, actor:)
    @document = document
    @actor    = actor
  end

  # Request review. Allowed from draft/rejected; blocked for content-incomplete
  # documents (#628/#634 — an empty shell must not be reviewable).
  def submit_for_review!
    unless @document.submittable_for_review?
      return conflict("Document is already #{@document.approval_status}")
    end
    if @document.respond_to?(:content_complete?) && !@document.content_complete?
      return Result.new(success: false, status_code: :unprocessable_entity,
                        error: "Cannot submit for review — missing required content: " \
                               "#{@document.content_completeness_gaps.join('; ')}")
    end

    @document.submit_for_review!(@actor)
    audit("submitted_for_review")
    Result.new(success: true, document: @document)
  end

  def approve!
    return forbidden unless can_approve?
    return conflict("Document is not pending review") unless @document.approval_pending?

    @document.mark_approved!(@actor)
    audit("approved")
    Result.new(success: true, document: @document)
  end

  def reject!(reason:)
    return forbidden unless can_approve?
    return conflict("Document is not pending review") unless @document.approval_pending?
    if reason.to_s.strip.empty?
      return Result.new(success: false, status_code: :unprocessable_entity,
                        error: "Rejection reason is required")
    end

    @document.mark_rejected!(reason.to_s.strip)
    audit("rejected", reason: reason.to_s.strip)
    Result.new(success: true, document: @document)
  end

  # Approver authority predicate (NIST AC-3 / AC-6) with separation of duties.
  def can_approve?(user = @actor)
    return false unless user
    # Separation of duties: a non-admin cannot approve a document they submitted.
    return false if !user.admin? && @document.submitted_by_user_id.present? &&
                    @document.submitted_by_user_id == user.id
    return true if user.admin?

    perm = APPROVE_PERMISSION[@document.class.name]
    return true if perm && user.has_permission?(perm)

    user.has_role?("policy_manager")
  end

  private

  def audit(event, extra = {})
    AuditEvent.log(
      action:   "#{@document.class.name.underscore}_#{event}",
      user:     @actor,
      subject:  @document,
      metadata: { name: @document.try(:name) }.merge(extra)
    )
  rescue => e
    Rails.logger.warn("Approval audit log failed: #{e.message}")
    raise unless Rails.env.production?
  end

  def forbidden
    Result.new(success: false, status_code: :forbidden,
               error: "Not authorized to approve this document")
  end

  def conflict(message)
    Result.new(success: false, status_code: :conflict, error: message)
  end
end
