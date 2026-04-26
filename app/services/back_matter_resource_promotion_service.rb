# Promotion workflow for BackMatterResource records.
#
# A managed or imported back-matter resource can be promoted to the
# authoritative tier (globally available, source = "authoritative") via a
# request → approve/reject flow. Approvals are gated to a specific set of
# instance and boundary roles per docs/dev/issue_rules.md.
#
# Approvers:
#   - Instance admin (users.admin = true)
#   - Instance-scoped role: policy_manager
#   - Authorization-boundary-scoped roles: ao, agency_ao, so_iso —
#     scoped to the resource's authorization boundary (resolved via the
#     resourceable parent document, when present)
#
# Library resources (no resourceable) can only be approved by admin or
# policy_manager — there is no boundary to anchor AO authority against.
#
# NIST 800-53:
#   AC-3   Access Enforcement (approver authority predicate)
#   AC-6   Least Privilege (admin / policy / AO bypass tiers)
#   AU-2   Audit Events (every state transition recorded)
#   AU-3   Content of Audit Records (who, when, what changed)
#   SA-10  Developer Configuration Management (back-matter traceability)
class BackMatterResourcePromotionService
  Result = Struct.new(:success, :resource, :error, :status_code, keyword_init: true) do
    def success? = success
  end

  APPROVER_BOUNDARY_ROLES = %w[ao agency_ao so_iso].freeze

  def initialize(resource:, actor:)
    @resource = resource
    @actor    = actor
    @batch    = SecureRandom.uuid
  end

  # Request promotion. Allowed when current promotion_status is
  # "none" or "rejected" and the resource is not already authoritative.
  def request_promotion!
    return Result.new(success: false, status_code: :conflict,
                      error: "Resource is already authoritative") if @resource.authoritative?
    unless %w[none rejected].include?(@resource.promotion_status)
      return Result.new(success: false, status_code: :conflict,
                        error: "Promotion is already in #{@resource.promotion_status}")
    end

    BackMatterResource.transaction do
      previous = @resource.promotion_status
      @resource.update!(promotion_status: "pending_review")
      log_change("promote", "promotion_status", previous, "pending_review")
    end

    Result.new(success: true, resource: @resource)
  end

  # Approve a pending promotion. Flips the resource into the authoritative
  # tier and globally_available = true, captures approver + timestamp.
  def approve!
    return forbidden_result unless can_approve?
    unless @resource.pending_promotion?
      return Result.new(success: false, status_code: :conflict,
                        error: "Promotion is not pending review")
    end

    BackMatterResource.transaction do
      previous = {
        promotion_status:   @resource.promotion_status,
        source:             @resource.source,
        globally_available: @resource.globally_available
      }

      @resource.update!(
        promotion_status:                       "approved",
        source:                                 "authoritative",
        globally_available:                     true,
        approved_by_user:                       @actor,
        approved_at:                            Time.current,
        promoted_from_organization_id:          @resource.organization_id,
        promoted_from_authorization_boundary_id: boundary_for_resource&.id
      )

      log_change("approve", "promotion_status", previous[:promotion_status], "approved")
      log_change("approve", "source",             previous[:source],             "authoritative")
      log_change("approve", "globally_available", previous[:globally_available], true)
    end

    Result.new(success: true, resource: @resource)
  end

  # Reject a pending promotion with a reason. Resource stays in its
  # current source tier; promotion_status flips to "rejected".
  def reject!(reason:)
    return forbidden_result unless can_approve?
    unless @resource.pending_promotion?
      return Result.new(success: false, status_code: :conflict,
                        error: "Promotion is not pending review")
    end
    if reason.to_s.strip.empty?
      return Result.new(success: false, status_code: :unprocessable_entity,
                        error: "Rejection reason is required")
    end

    BackMatterResource.transaction do
      previous = @resource.promotion_status
      @resource.update!(promotion_status: "rejected", rejection_reason: reason.to_s.strip)
      log_change("reject", "promotion_status", previous, "rejected")
      log_change("reject", "rejection_reason", nil, reason.to_s.strip)
    end

    Result.new(success: true, resource: @resource)
  end

  # Approver authority predicate (NIST AC-3 / AC-6).
  def can_approve?(user = @actor)
    return false unless user
    return true  if user.admin?
    return true  if user.has_role?("policy_manager")

    boundary = boundary_for_resource
    return false unless boundary

    APPROVER_BOUNDARY_ROLES.any? do |role|
      user.has_role?(role, authorization_boundary_id: boundary.id)
    end
  end

  private

  def boundary_for_resource
    return @boundary_for_resource if defined?(@boundary_for_resource)

    parent = @resource.resourceable
    @boundary_for_resource =
      if parent.nil?
        nil
      elsif parent.respond_to?(:authorization_boundary)
        parent.authorization_boundary
      elsif parent.respond_to?(:authorization_boundary_id) && parent.authorization_boundary_id
        AuthorizationBoundary.find_by(id: parent.authorization_boundary_id)
      end
  end

  def log_change(change_type, field, from, to)
    BackMatterResourceChange.create!(
      back_matter_resource: @resource,
      changed_by_user:      @actor,
      change_type:          change_type,
      field:                field,
      from_value:           from.to_s,
      to_value:             to.to_s,
      batch_uuid:           @batch,
      changed_at:           Time.current
    )
  end

  def forbidden_result
    Result.new(success: false, status_code: :forbidden,
               error: "Not authorized to approve promotion for this resource")
  end
end
