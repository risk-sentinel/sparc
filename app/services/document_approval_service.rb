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
  #
  # #1275 — a CDEF may ask for a wider scope ("global" or "instance"), applied
  # when it is approved. Blank keeps the scope it has.
  def submit_for_review!(requested_scope: nil)
    unless @document.submittable_for_review?
      return conflict("Document is already #{@document.approval_status}")
    end
    if @document.respond_to?(:content_complete?) && !@document.content_complete?
      return Result.new(success: false, status_code: :unprocessable_content,
                        error: "Cannot submit for review — missing required content: " \
                               "#{@document.content_completeness_gaps.join('; ')}")
    end
    requested_scope = requested_scope.presence
    if requested_scope && (refusal = scope_request_refusal(requested_scope))
      return Result.new(success: false, status_code: :unprocessable_content, error: refusal)
    end

    @document.transaction do
      @document.submit_for_review!(@actor)
      @document.update!(requested_scope: requested_scope) if @document.is_a?(CdefDocument)
    end
    audit("submitted_for_review", requested_scope ? { requested_scope: requested_scope } : {})
    Result.new(success: true, document: @document)
  end

  def approve!
    return refused("approve") unless can_approve?
    return conflict("Document is not pending review") unless @document.approval_pending?

    # #1275 — the approval and the scope it was asked for land together.
    granted = @document.try(:requested_scope)
    begin
      @document.transaction do
        CdefScopeService.apply_requested!(@document) if granted
        @document.mark_approved!(@actor)
      end
    rescue ArgumentError => e
      @document.reload
      return conflict(e.message)
    end
    audit("approved", granted ? { scope: granted } : {})
    Result.new(success: true, document: @document)
  end

  def reject!(reason:)
    return refused("reject") unless can_approve?
    return conflict("Document is not pending review") unless @document.approval_pending?
    if reason.to_s.strip.empty?
      return Result.new(success: false, status_code: :unprocessable_content,
                        error: "Rejection reason is required")
    end

    @document.transaction do
      @document.mark_rejected!(reason.to_s.strip)
      @document.update!(requested_scope: nil) if @document.try(:requested_scope)
    end
    audit("rejected", reason: reason.to_s.strip)
    Result.new(success: true, document: @document)
  end

  # Approver authority predicate (NIST AC-3 / AC-6) with separation of duties.
  def can_approve?(user = @actor)
    return false unless user
    # Separation of duties: a non-admin cannot approve a document they submitted.
    return false if !user.admin? && @document.submitted_by_user_id.present? &&
                    @document.submitted_by_user_id == user.id
    return true if user.instance_administrator?
    return true if approver_of_document?(user)

    user.has_role?("policy_manager")
  end

  # #1275 — may this caller publish over the API without the document going
  # through review (ApiPublicationGuard)? For a CDEF, only an instance-level
  # approver: a boundary approver submits it and has someone else approve it
  # (owner, 2026-10-24). Catalogs and profiles are approved at instance level
  # only, so for them it is can_approve?.
  def may_publish_without_review?(user = @actor)
    return false unless can_approve?(user)
    return true unless @document.is_a?(CdefDocument)

    user.instance_administrator? || CdefWriteAccess.instance_approver?(user) || user.has_role?("policy_manager")
  end

  private

  # #1275 — a CDEF is approved under the boundary rule #1258 set for writes:
  # `cdef.approve` across the instance, or on the boundary its scope was set
  # to. Catalogs and profiles are library documents, approved at instance level.
  def approver_of_document?(user)
    return CdefWriteAccess.may_approve?(user, @document) if @document.is_a?(CdefDocument)

    perm = APPROVE_PERMISSION[@document.class.name]
    perm.present? && user.has_permission?(perm)
  end

  # #1275 — only a CDEF has a scope to widen.
  def scope_request_refusal(scope)
    return "Only a component definition can ask for a wider scope." unless @document.is_a?(CdefDocument)

    CdefScopeService.request_refusal(@document, scope)
  end

  # #1275 — a refused approve or reject is recorded, as a refused write is
  # (owner, 2026-10-24). AC-3 / AU-2.
  def refused(attempt)
    audit("approval_refused", attempted: attempt)
    forbidden
  end

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
