# frozen_string_literal: true

# #1249 — REST API for a boundary's OWN back-matter: the documents that describe
# the system (diagrams, inventory, PPSM, CRM) rather than one of its documents.
#
#   GET    /api/v1/authorization_boundaries/:authorization_boundary_id/back_matter_resources
#   POST   /api/v1/authorization_boundaries/:authorization_boundary_id/back_matter_resources
#   PATCH  /api/v1/authorization_boundaries/:authorization_boundary_id/back_matter_resources/:id
#   DELETE /api/v1/authorization_boundaries/:authorization_boundary_id/back_matter_resources/:id
#
# The API equivalent of the boundary page's Back Matter section
# (BackMatterResourcesController under /authorization_boundaries/:id), with the
# same rule on both surfaces, checked against THIS boundary:
#
#   read   authorization_boundaries.read AND back_matter.read
#   write  back_matter.write
#
# Editable in any boundary status (owner, 2026-10-22). The Boundary
# Completeness row "Back-matter documents" counts these.
#
# NIST 800-53: AC-3 (access enforcement), AU-12 (audit record generation),
# SA-10 (configuration management of system documentation).
class Api::V1::BoundaryBackMatterResourcesController < Api::V1::BaseController
  READ_KEYS = AuthorizationBoundary::BACK_MATTER_READ_PERMISSIONS
  WRITE_KEY = AuthorizationBoundary::BACK_MATTER_WRITE_PERMISSION

  before_action :set_boundary
  before_action :authorize_read!,  only: :index
  before_action :authorize_write!, only: %i[create update destroy]
  before_action :set_resource, only: %i[update destroy]

  # GET .../back_matter_resources
  def index
    result = paginate(@boundary.back_matter_resources.order(:title, :id), items: 50)
    render json: {
      data: result[:data].map { |resource| serialize_back_matter_resource(resource, detailed: true) },
      meta: result[:meta]
    }
  end

  # POST .../back_matter_resources
  def create
    resource = @boundary.back_matter_resources.build(resource_params)
    resource.uuid = SecureRandom.uuid
    resource.source = "managed"
    resource.organization = current_user.organizations.first if current_user&.organizations&.any?
    resource.save!

    audit_log("back_matter_resource_created", subject: resource,
              metadata: { title: resource.title, boundary: @boundary.slug })
    render json: { data: serialize_back_matter_resource(resource, detailed: true) }, status: :created
  end

  # PATCH .../back_matter_resources/:id
  def update
    @resource.update!(resource_params)

    audit_log("back_matter_resource_updated", subject: @resource,
              metadata: { title: @resource.title, boundary: @boundary.slug })
    render json: { data: serialize_back_matter_resource(@resource, detailed: true) }
  end

  # DELETE .../back_matter_resources/:id
  def destroy
    audit_log("back_matter_resource_deleted", subject: @resource,
              metadata: { title: @resource.title, uuid: @resource.uuid, boundary: @boundary.slug })
    @resource.destroy!

    render json: { data: { id: @resource.id, deleted: true } }
  end

  private

  # Numeric id or slug, as every other boundary-nested API route accepts.
  def set_boundary
    param = params[:authorization_boundary_id].to_s
    @boundary = AuthorizationBoundary.find_by(slug: param) || AuthorizationBoundary.find(param)
  end

  # Scoped to the boundary: a resource id belonging to anything else is a 404.
  def set_resource
    @resource = @boundary.back_matter_resources.find(params[:id])
  end

  def authorize_read!
    READ_KEYS.each { |key| authorize_permission!(key, authorization_boundary_id: @boundary.id) }
  end

  def authorize_write!
    authorize_permission!(WRITE_KEY, authorization_boundary_id: @boundary.id)
  end

  # The fields the boundary page's form writes. The owner is the boundary in the
  # path; it is never taken from the body.
  def resource_params
    permit_strictly(:back_matter_resource, :title, :description, :href, :media_type, :rel, :globally_available)
  end
end
