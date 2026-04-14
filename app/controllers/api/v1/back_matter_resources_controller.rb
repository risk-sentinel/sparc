# REST API for back-matter resource management.
#
# Provides CRUD operations for OSCAL back-matter resources with
# control-level linking, organization scoping, and global availability.
# Supports the authoritative layer for enterprise provider publishing.
#
# Endpoints:
#   GET    /api/v1/back_matter_resources          — list (paginated, filterable)
#   GET    /api/v1/back_matter_resources/:id      — show with linked controls
#   POST   /api/v1/back_matter_resources          — create with OSCAL validations
#   PATCH  /api/v1/back_matter_resources/:id      — update
#   DELETE /api/v1/back_matter_resources/:id      — delete + unlink all controls
#   POST   /api/v1/back_matter_resources/:id/link   — link to a control
#   DELETE /api/v1/back_matter_resources/:id/unlink — unlink from a control
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (permission-based RBAC)
#   AU-12 Audit Record Generation (all mutations logged)
#   SA-10 Developer Configuration Management (back-matter traceability)
#
class Api::V1::BackMatterResourcesController < Api::V1::BaseController
  before_action :set_resource, only: %i[show update destroy link unlink]
  before_action :authorize_read!, only: %i[index show]
  before_action :authorize_write!, only: %i[create update destroy link unlink]

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
    return if current_user.has_permission?("back_matter.write")

    raise NotAuthorizedError, "Not authorized to manage back-matter resources"
  end
end
