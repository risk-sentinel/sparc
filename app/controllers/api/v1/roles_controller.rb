# frozen_string_literal: true

# #1014 — REST API for RBAC role definitions.
#
#   GET    /api/v1/roles
#   POST   /api/v1/roles
#   GET    /api/v1/roles/:id
#   PATCH  /api/v1/roles/:id
#   DELETE /api/v1/roles/:id
#
# Found by the missing-endpoint axis of #995. Roles carry the permission sets
# every authorization check in the application reads, and they could be created,
# edited and deleted only through a browser — so an operator could not review or
# reproduce an instance's RBAC configuration programmatically, which is exactly
# what an accreditation package needs to show.
#
# This is the `Role`/`UserRole` system, NOT the legacy membership roster. The
# two coexist and #929 turned on telling them apart; a role here grants
# permissions, a roster entry does not.
#
# Instance Admin is not a role — it is the `users.admin` boolean — so it cannot
# be created or granted here.
#
# NIST 800-53 Controls:
#   AC-2 Account Management, AC-3 Access Enforcement, AC-6 Least Privilege,
#   AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::RolesController < Api::V1::BaseController
  before_action :authorize_admin!
  before_action :set_role, only: %i[show update destroy]

  # GET /api/v1/roles
  def index
    scope = Role.sorted
    scope = scope.where(scope: params[:scope]) if params[:scope].present?
    result = paginate(scope, items: 50)

    render json: {
      data: result[:data].map { |role| serialize(role) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/roles/:id
  def show
    render json: { data: serialize(@role, detailed: true) }
  end

  # POST /api/v1/roles
  def create
    role = Role.new(role_params)
    role.assign_permissions(permission_params)
    role.save!

    audit_log("role_created", subject: role,
              metadata: { role_id: role.id, role_name: role.name })
    render json: { data: serialize(role, detailed: true) }, status: :created
  end

  # PATCH /api/v1/roles/:id
  def update
    @role.assign_attributes(role_params)
    # Permissions are replaced wholesale, matching the web form: the request
    # states the role's complete permission set, so a key omitted is a key
    # revoked. A partial merge would make "remove this permission" impossible
    # to express.
    @role.assign_permissions(permission_params) if params[:role]&.key?(:permissions)
    @role.save!

    audit_log("role_updated", subject: @role,
              metadata: { role_id: @role.id, role_name: @role.name })
    render json: { data: serialize(@role, detailed: true) }
  end

  # DELETE /api/v1/roles/:id
  def destroy
    # Mirrors the web guard. Deleting an assigned role would strip access from
    # every holder at once, with nothing recording who lost what.
    if @role.user_roles.exists?
      return render json: {
        error: "Cannot delete a role that is assigned to users. Remove all assignments first.",
        details: [ "#{@role.user_roles.count} assignment(s) remain" ]
      }, status: :unprocessable_entity
    end

    audit_log("role_deleted", subject: @role,
              metadata: { role_id: @role.id, role_name: @role.name })
    @role.destroy!

    render json: { data: { id: @role.id, name: @role.name, deleted: true } }
  end

  private

  def set_role
    @role = Role.find(params[:id])
  end

  def role_params
    permit_strictly(:role, :name, :display_name, :scope, :description, :sort_order,
      also_accepts: %i[permissions])
  end

  # The permission map, as `{"catalogs.read" => true}`. Unknown keys are
  # ignored rather than refused: `assign_permissions` builds the map from
  # Role::PERMISSION_KEYS, so a key the application does not enforce cannot be
  # written, and a stale key from an older instance should not fail an
  # otherwise valid request. `available_permissions` on the show response tells
  # a caller what the current set is.
  def permission_params
    raw = params.dig(:role, :permissions)
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end

  def serialize(role, detailed: false)
    data = {
      id: role.id,
      name: role.name,
      display_name: role.display_name,
      scope: role.scope,
      sort_order: role.sort_order,
      assignment_count: role.user_roles.count
    }

    if detailed
      data[:description] = role.description
      # Only the granted keys, so a reader sees what the role DOES rather than
      # scanning ~60 booleans for the true ones.
      data[:permissions] = role.permissions.to_h.select { |_key, granted| granted }.keys.sort
      data[:available_permissions] = Role::PERMISSION_KEYS
      data[:created_at] = role.created_at.utc.iso8601
      data[:updated_at] = role.updated_at.utc.iso8601
    end

    data
  end

  def authorize_admin!
    raise NotAuthorizedError, "Not authorized to manage roles" unless current_user.admin?
  end
end
