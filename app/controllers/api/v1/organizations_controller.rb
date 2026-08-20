# frozen_string_literal: true

# #1012 — REST API for organizations, their boundary assignments and their
# membership.
#
#   GET    /api/v1/organizations
#   POST   /api/v1/organizations
#   GET    /api/v1/organizations/:id
#   PATCH  /api/v1/organizations/:id
#   POST   /api/v1/organizations/:id/deactivate
#   POST   /api/v1/organizations/:id/reactivate
#   POST   /api/v1/organizations/:id/boundaries
#   GET    /api/v1/organizations/:id/members
#   POST   /api/v1/organizations/:id/members
#   DELETE /api/v1/organizations/:id/members/:membership_id
#
# Found by the missing-endpoint axis of #995. Organizations scope boundaries and
# documents, and membership decides who can see what, yet creating one,
# assigning a boundary to it and adding or removing a member were all
# browser-only.
#
# **Organizations are never hard-deleted.** They are deactivated and
# reactivated, preserving the UUID for audit traceability — so there is no
# `destroy` here, and `deactivate` is the closest thing to one.
#
# Boundary assignment goes through BoundaryOrganizationAssigner, the same object
# the web screen uses, so the authorization matrix for assign-versus-move lives
# in one place rather than being restated per surface (AC-3).
#
# NIST 800-53 Controls:
#   AC-2 Account Management (membership), AC-3 Access Enforcement,
#   AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::OrganizationsController < Api::V1::BaseController
  before_action :authorize_admin!
  before_action :set_organization,
                only: %i[show update deactivate reactivate assign_boundary
                         members add_member remove_member]

  # GET /api/v1/organizations
  def index
    scope = Organization.order(:name)
    if params[:q].present?
      scope = scope.where(
        "name ILIKE :q OR description ILIKE :q OR contact_email ILIKE :q OR contact_person ILIKE :q",
        q: "%#{params[:q]}%"
      )
    end
    result = paginate(scope, items: 50)

    render json: {
      data: result[:data].map { |organization| serialize(organization) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/organizations/:id
  def show
    render json: { data: serialize(@organization, detailed: true) }
  end

  # POST /api/v1/organizations
  def create
    organization = Organization.new(organization_params)
    organization.save!

    audit_log("organization_created", subject: organization,
              metadata: { organization_id: organization.id, name: organization.name })
    render json: { data: serialize(organization, detailed: true) }, status: :created
  end

  # PATCH /api/v1/organizations/:id
  def update
    @organization.update!(organization_params)

    audit_log("organization_updated", subject: @organization,
              metadata: { organization_id: @organization.id, name: @organization.name })
    render json: { data: serialize(@organization, detailed: true) }
  end

  # POST /api/v1/organizations/:id/deactivate
  def deactivate
    @organization.deactivate!

    audit_log("organization_deactivated", subject: @organization,
              metadata: { organization_id: @organization.id, name: @organization.name })
    render json: { data: serialize(@organization.reload, detailed: true) }
  end

  # POST /api/v1/organizations/:id/reactivate
  def reactivate
    @organization.reactivate!

    audit_log("organization_reactivated", subject: @organization,
              metadata: { organization_id: @organization.id, name: @organization.name })
    render json: { data: serialize(@organization.reload, detailed: true) }
  end

  # POST /api/v1/organizations/:id/boundaries
  #
  # Assign a boundary to this organization, or move it from another. The
  # assigner enforces the matrix; this endpoint does not restate it.
  def assign_boundary
    boundary = AuthorizationBoundary.find(params[:authorization_boundary_id])
    previous = boundary.organization

    BoundaryOrganizationAssigner.new(
      boundary: boundary, organization: @organization, actor: current_user
    ).call

    audit_log("organization_boundary_assigned", subject: @organization,
              metadata: { organization_id: @organization.id,
                          authorization_boundary_id: boundary.id,
                          moved_from_organization_id: previous&.id })

    render json: {
      data: {
        organization_id: @organization.id,
        authorization_boundary_id: boundary.id,
        moved_from_organization_id: previous&.id,
        moved: previous.present? && previous != @organization
      }
    }
  end

  # GET /api/v1/organizations/:id/members
  def members
    result = paginate(@organization.organization_memberships.includes(:user).order(:id), items: 50)

    render json: {
      data: result[:data].map { |membership| serialize_membership(membership) },
      meta: result[:meta]
    }
  end

  # POST /api/v1/organizations/:id/members
  def add_member
    user = User.find(params[:user_id])
    membership = @organization.organization_memberships.build(user: user, role: params[:role])
    membership.save!

    audit_log("organization_member_added", subject: @organization,
              metadata: { organization_id: @organization.id, target_user_id: user.id,
                          target_email: user.email, role: params[:role] })

    render json: { data: serialize_membership(membership) }, status: :created
  end

  # DELETE /api/v1/organizations/:id/members/:membership_id
  def remove_member
    membership = @organization.organization_memberships.find(params[:membership_id])
    user = membership.user

    audit_log("organization_member_removed", subject: @organization,
              metadata: { organization_id: @organization.id, target_user_id: user.id,
                          target_email: user.email, role: membership.role })
    membership.destroy!

    render json: {
      data: { id: membership.id, user_id: user.id, organization_id: @organization.id,
              removed: true }
    }
  end

  private

  # Organizations are slug-addressed in the web routes; both spellings work
  # here so an id from a list response is usable directly.
  def set_organization
    param = params[:id].to_s
    @organization = Organization.find_by(slug: param) || Organization.find(param)
  end

  def organization_params
    permit_strictly(:organization,
      :name, :description, :address, :contact_person, :contact_email
    )
  end

  def serialize(organization, detailed: false)
    data = {
      id: organization.id,
      uuid: organization.try(:uuid),
      slug: organization.slug,
      name: organization.name,
      active: organization.try(:active?),
      member_count: organization.organization_memberships.count,
      boundary_count: organization.authorization_boundaries.count
    }

    if detailed
      data[:description] = organization.description
      data[:address] = organization.address
      data[:contact_person] = organization.contact_person
      data[:contact_email] = organization.contact_email
      data[:created_at] = organization.created_at.utc.iso8601
      data[:updated_at] = organization.updated_at.utc.iso8601
    end

    data
  end

  def serialize_membership(membership)
    {
      id: membership.id,
      organization_id: membership.organization_id,
      user_id: membership.user_id,
      user_email: membership.user&.email,
      role: membership.role,
      role_label: membership.try(:role_label),
      created_at: membership.created_at.utc.iso8601
    }
  end

  def authorize_admin!
    raise NotAuthorizedError, "Not authorized to manage organizations" unless current_user.admin?
  end
end
