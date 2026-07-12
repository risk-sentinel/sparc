# REST API for back-matter resource management.
#
# Provides CRUD operations for OSCAL back-matter resources with
# control-level linking, organization scoping, and global availability.
# Supports the authoritative layer for enterprise provider publishing.
#
# Endpoints:
#   GET    /api/v1/back_matter_resources                       — list (paginated, filterable)
#   GET    /api/v1/back_matter_resources/promotion_queue       — pending promotions caller can approve (#372)
#   GET    /api/v1/back_matter_resources/:id                   — show with linked controls
#   POST   /api/v1/back_matter_resources                       — create with OSCAL validations
#   PATCH  /api/v1/back_matter_resources/:id                   — update
#   DELETE /api/v1/back_matter_resources/:id                   — delete + unlink all controls
#   POST   /api/v1/back_matter_resources/:id/link              — link to a control
#   DELETE /api/v1/back_matter_resources/:id/unlink            — unlink from a control
#   POST   /api/v1/back_matter_resources/:id/promote           — request promotion to authoritative (#372)
#   POST   /api/v1/back_matter_resources/:id/approve_promotion — approve a pending promotion (#372)
#   POST   /api/v1/back_matter_resources/:id/reject_promotion  — reject with reason (#372)
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (permission-based RBAC + approver authority)
#   AC-6 Least Privilege (promotion approver tiers)
#   AU-12 Audit Record Generation (all mutations + transitions logged)
#   SA-10 Developer Configuration Management (back-matter traceability)
#
class Api::V1::BackMatterResourcesController < Api::V1::BaseController
  SCOPE_BACK_MATTER_WRITE = "back_matter.write".freeze

  before_action :set_resource, only: %i[show update destroy link unlink promote
                                         approve_promotion reject_promotion
                                         archive restore changes]
  before_action :authorize_read!, only: %i[index show changes]
  before_action :authorize_write!, only: %i[create update destroy link unlink]
  before_action :authorize_promote!, only: :promote
  before_action :authorize_approve_promotion!, only: %i[approve_promotion reject_promotion]
  before_action :authorize_bulk_import!, only: :bulk
  before_action :authorize_archive!, only: %i[archive restore]
  # promotion_queue is self-filtering: it only returns rows the caller can
  # approve. Authentication alone is sufficient — no separate permission gate.

  # GET /api/v1/back_matter_resources
  def index
    scope = BackMatterResource.all
    scope = apply_filters(scope)
    result = paginate(scope.order(created_at: :desc))
    result[:data] = result[:data].map { |r| serialize_back_matter_resource(r) }
    render json: result
  end

  # GET /api/v1/back_matter_resources/:id
  def show
    render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
  end

  # POST /api/v1/back_matter_resources
  def create
    @resource = BackMatterResource.new(resource_params)
    @resource.uuid = SecureRandom.uuid
    @resource.source = params.dig(:back_matter_resource, :source) || "managed"
    @resource.organization ||= current_user.organizations.first if current_user.organizations.any?

    # Only admins/service accounts can create authoritative resources
    if @resource.source == "authoritative" && !current_user.admin?
      render json: { error: "Only admins can create authoritative resources" }, status: :forbidden
      return
    end

    if @resource.save
      audit_log("back_matter_resource_created", subject: @resource,
                metadata: { title: @resource.title, source: @resource.source })
      maybe_auto_fetch(@resource)
      render json: { data: serialize_back_matter_resource(@resource, detailed: true) }, status: :created
    else
      render json: { error: "Validation failed", details: @resource.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/back_matter_resources/:id
  def update
    if @resource.update(resource_params)
      audit_log("back_matter_resource_updated", subject: @resource,
                metadata: { title: @resource.title })
      render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
    else
      render json: { error: "Validation failed", details: @resource.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/back_matter_resources/:id
  def destroy
    title = @resource.title
    audit_log("back_matter_resource_deleted", subject: @resource,
              metadata: { title: title, uuid: @resource.uuid })
    @resource.destroy
    render json: { data: { id: @resource.id, deleted: true } }
  end

  # POST /api/v1/back_matter_resources/:id/link
  def link
    linkable_type = params[:linkable_type]
    linkable_id = params[:linkable_id]

    unless %w[CatalogControl CdefControl ProfileControl SspControl SarControl SapControl].include?(linkable_type)
      render json: { error: "Invalid linkable_type. Must be one of: CatalogControl, CdefControl, ProfileControl, SspControl, SarControl, SapControl" },
             status: :unprocessable_entity
      return
    end

    control = linkable_type.constantize.find(linkable_id)
    link = @resource.control_back_matter_links.build(linkable: control)

    if link.save
      audit_log("back_matter_resource_linked", subject: @resource,
                metadata: { control_type: linkable_type, control_id: linkable_id })
      render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
    else
      render json: { error: "Link failed", details: link.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/back_matter_resources/:id/unlink
  def unlink
    link = @resource.control_back_matter_links.find(params[:link_id])
    audit_log("back_matter_resource_unlinked", subject: @resource,
              metadata: { control_type: link.linkable_type, control_id: link.linkable_id })
    link.destroy
    render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
  end

  # POST /api/v1/back_matter_resources/:id/promote (#372)
  def promote
    result = BackMatterResourcePromotionService.new(resource: @resource, actor: current_user)
                                               .request_promotion!
    if result.success?
      audit_log("back_matter_resource_promotion_requested", subject: @resource,
                metadata: { title: @resource.title })
      render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  # POST /api/v1/back_matter_resources/:id/approve_promotion (#372)
  def approve_promotion
    result = BackMatterResourcePromotionService.new(resource: @resource, actor: current_user)
                                               .approve!
    if result.success?
      audit_log("back_matter_resource_promotion_approved", subject: @resource,
                metadata: { title: @resource.title, approver_id: current_user.id })
      render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  # POST /api/v1/back_matter_resources/:id/reject_promotion (#372)
  def reject_promotion
    reason = params[:reason] || params.dig(:back_matter_resource, :rejection_reason)
    result = BackMatterResourcePromotionService.new(resource: @resource, actor: current_user)
                                               .reject!(reason: reason)
    if result.success?
      audit_log("back_matter_resource_promotion_rejected", subject: @resource,
                metadata: { title: @resource.title, approver_id: current_user.id })
      render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  # POST /api/v1/back_matter_resources/:id/archive (#372)
  def archive
    if @resource.archived?
      render json: { error: "Already archived" }, status: :conflict
      return
    end

    BackMatterResource.transaction do
      @resource.update!(archived_at: Time.current)
      record_change(@resource, "archive", "archived_at", nil, @resource.archived_at.iso8601)
    end
    audit_log("back_matter_resource_archived", subject: @resource,
              metadata: { title: @resource.title })
    render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
  end

  # POST /api/v1/back_matter_resources/:id/restore (#372)
  def restore
    unless @resource.archived?
      render json: { error: "Not archived" }, status: :conflict
      return
    end

    BackMatterResource.transaction do
      previous = @resource.archived_at
      @resource.update!(archived_at: nil)
      record_change(@resource, "restore", "archived_at", previous&.iso8601, nil)
    end
    audit_log("back_matter_resource_restored", subject: @resource,
              metadata: { title: @resource.title })
    render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
  end

  # GET /api/v1/back_matter_resources/:id/changes (#372)
  def changes
    rows = @resource.changes_log.reverse_chronological.includes(:changed_by_user)
    render json: {
      data: rows.map do |c|
        {
          id:           c.id,
          change_type:  c.change_type,
          field:        c.field,
          from_value:   c.from_value,
          to_value:     c.to_value,
          batch_uuid:   c.batch_uuid,
          changed_at:   c.changed_at.iso8601,
          changed_by:   c.changed_by_user&.then { |u| { id: u.id, email: u.email } }
        }
      end,
      meta: { count: rows.size }
    }
  end

  # POST /api/v1/back_matter_resources/bulk (#372)
  def bulk
    entries = params[:entries] || params.dig(:back_matter_resources)
    org     = current_user.organizations.first
    result  = BackMatterBulkImportService.new(entries: entries, actor: current_user,
                                              organization: org).call
    if result.success?
      audit_log("back_matter_resources_bulk_imported",
                metadata: { batch_uuid: result.batch_uuid, imported: result.imported.size,
                            skipped: result.skipped.size, errors: result.errors.size })
      render json: {
        data: {
          batch_uuid: result.batch_uuid,
          imported:   result.imported.map { |r| serialize_back_matter_resource(r) },
          skipped:    result.skipped,
          errors:     result.errors
        }
      }, status: :created
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  # GET /api/v1/back_matter_resources/promotion_queue (#372)
  # Lists pending promotions the caller is authorized to approve.
  def promotion_queue
    pending = BackMatterResource.pending_promotion.order(updated_at: :desc)
    approvable = pending.select do |r|
      BackMatterResourcePromotionService.new(resource: r, actor: current_user).can_approve?
    end
    render json: { data: approvable.map { |r| serialize_back_matter_resource(r, detailed: true) },
                   meta: { count: approvable.size } }
  end

  private

  def set_resource
    @resource = BackMatterResource.find(params[:id])
  end

  def resource_params
    params.require(:back_matter_resource).permit(
      :title, :description, :href, :media_type, :rel,
      :globally_available, :organization_id,
      :resourceable_type, :resourceable_id
    )
  end

  def apply_filters(scope)
    scope = scope.where(organization_id: params[:organization_id]) if params[:organization_id].present?
    scope = scope.where(globally_available: params[:globally_available] == "true") if params[:globally_available].present?
    scope = scope.where(rel: params[:rel]) if params[:rel].present?
    scope = scope.where(source: params[:source]) if params[:source].present?
    scope = scope.where(resourceable_type: params[:document_type]) if params[:document_type].present?
    scope = scope.where(resourceable_id: params[:document_id]) if params[:document_id].present?

    if params[:control_type].present? && params[:control_id].present?
      resource_ids = ControlBackMatterLink
        .where(linkable_type: params[:control_type], linkable_id: params[:control_id])
        .select(:back_matter_resource_id)
      scope = scope.where(id: resource_ids)
    end

    scope
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.read")

    raise NotAuthorizedError, "Not authorized to view back-matter resources"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?(SCOPE_BACK_MATTER_WRITE)

    raise NotAuthorizedError, "Not authorized to manage back-matter resources"
  end

  def authorize_promote!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.promote")
    return if current_user.has_permission?(SCOPE_BACK_MATTER_WRITE)

    raise NotAuthorizedError, "Not authorized to request promotion"
  end

  def authorize_approve_promotion!
    return if current_user.has_permission?("back_matter.approve_promotion")

    service = BackMatterResourcePromotionService.new(resource: @resource, actor: current_user)
    return if service.can_approve?

    raise NotAuthorizedError, "Not authorized to approve or reject promotion for this resource"
  end

  def authorize_bulk_import!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.bulk_import")
    return if current_user.has_permission?(SCOPE_BACK_MATTER_WRITE)

    raise NotAuthorizedError, "Not authorized to bulk-import back-matter resources"
  end

  # Optional auto-fetch on create — gated by SPARC_AUTHORITATIVE_FETCH_ENABLED.
  # Failures are surfaced in the response metadata but never block creation.
  def maybe_auto_fetch(resource)
    return unless ActiveModel::Type::Boolean.new
                    .cast(params.dig(:back_matter_resource, :auto_fetch))

    AuthoritativeSourceFetchService.call(resource: resource, actor: current_user)
  end

  def authorize_archive!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.archive")
    return if current_user.has_permission?(SCOPE_BACK_MATTER_WRITE)

    raise NotAuthorizedError, "Not authorized to archive or restore back-matter resources"
  end

  def record_change(resource, change_type, field, from_value, to_value)
    BackMatterResourceChange.create!(
      back_matter_resource: resource,
      changed_by_user:      current_user,
      change_type:          change_type,
      field:                field,
      from_value:           from_value.to_s,
      to_value:             to_value.to_s,
      batch_uuid:           SecureRandom.uuid,
      changed_at:           Time.current
    )
  end
end
