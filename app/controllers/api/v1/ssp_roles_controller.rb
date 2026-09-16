# REST API for the roles a System Security Plan declares (#1116).
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# A `role-id` must reference a role declared in `metadata.roles`. Until now an
# SSP declared exactly three, hardcoded in the exporter, and the statement editor
# took responsible roles as FREE TEXT — so an author could type `isso` and
# produce a document whose reference resolved to nothing. That is a REFERENTIAL
# break, not a schema one: the document validates cleanly and a consuming tool
# resolving the reference finds nothing.
#
# Roles live in `metadata_extra["roles"]`, which the OscalMetadata concern
# already exposes. This is the surface that lets a pipeline declare them, so the
# UI is a thin client over the same endpoints rather than the only way.
#
# Endpoints (nested under /api/v1/ssp_documents/:ssp_document_id):
#   GET    .../roles        — declared roles, the boundary vocabulary, and NIST
#                              ids not yet declared
#   POST   .../roles        — declare a role: by `membership_role` (normal) or
#                              by a typed `id` (the exception, #1134)
#   PATCH  .../roles/:id    — retitle one
#   DELETE .../roles/:id    — undeclare one (refused while still referenced)
#
# `:id` is the OSCAL role-id, not a database key — roles are a JSON document
# structure, and there is no roles table.
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (boundary-scoped ssp.read / ssp.write)
#   AU-12 Audit Record Generation (every mutation logged)
#   SI-10 Information Input Validation (a role-id must be an NCName token, and a
#         role still referenced by a statement cannot be removed)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::SspRolesController < Api::V1::BaseController
  # OSCAL role-id is an NCName token: letters, digits, hyphen, underscore, dot;
  # it may not start with a digit. A URI here would be a category error — the
  # deployment's namespace belongs on a PROP of the role, never on its id.
  ROLE_ID_FORMAT = /\A[A-Za-z_][\w.-]*\z/

  before_action :set_ssp_document
  before_action :authorize_read!, only: %i[index]
  before_action :authorize_write!, only: %i[create update destroy]

  # GET /api/v1/ssp_documents/:ssp_document_id/roles
  def index
    render json: {
      data: @ssp_document.declared_roles.map { |r| serialize(r) },
      meta: {
        # Offered so a client adopts NIST's canonical id rather than minting one.
        # Not a restriction: NIST sets allow-other="yes" on role-id, so a
        # deployment-defined role is legal — it just has to be declared.
        suggested: @ssp_document.undeclared_suggested_roles,
        # #1134 — the NORMAL path. The boundary-membership vocabulary a role is
        # declared from, each showing the OSCAL role it resolves to, so a client
        # picks by label and never types an id.
        membership_roles: @ssp_document.membership_role_choices,
        oscal_version: @ssp_document.oscal_version || OscalSchema::DEFAULT_VERSION
      }
    }
  end

  # POST /api/v1/ssp_documents/:ssp_document_id/roles
  #
  # `role[membership_role]` is the normal path (#1134): the role is resolved
  # from the boundary vocabulary, to NIST's id where one exists and to an
  # organization-defined role otherwise. `role[id]` stays legal — NIST sets
  # allow-other="yes" — but is the exception.
  def create
    membership_role = role_params[:membership_role].to_s.strip
    if membership_role.present?
      return render_api_error("send role[membership_role] or role[id], not both") if role_params[:id].present?

      return create_from_membership_role(membership_role)
    end

    id    = role_params[:id].to_s.strip
    title = role_params[:title].to_s.strip

    return render_api_error("role id is required") if id.blank?
    return render_api_error("role id #{id.inspect} is not a valid NCName token") unless id.match?(ROLE_ID_FORMAT)
    return render_api_error("role #{id.inspect} is already declared") if @ssp_document.declared_role_ids.include?(id)

    role = if ActiveModel::Type::Boolean.new.cast(role_params[:organization_defined])
             OscalRole.organization_defined(id, title.presence || OscalRole.humanize(id))
    else
             { "id" => id, "title" => title.presence || OscalRole.humanize(id) }
    end

    write_roles(@ssp_document.declared_roles + [ role ])
    audit_log("ssp_role_declared", subject: @ssp_document, metadata: { role_id: id })

    render json: { data: serialize(role) }, status: :created
  end

  # PATCH /api/v1/ssp_documents/:ssp_document_id/roles/:id
  def update
    role = find_role!
    return if performed?

    updated = role.merge("title" => role_params[:title].to_s.strip.presence || role["title"])
    write_roles(@ssp_document.declared_roles.map { |r| r["id"] == role["id"] ? updated : r })
    audit_log("ssp_role_updated", subject: @ssp_document, metadata: { role_id: role["id"] })

    render json: { data: serialize(updated) }
  end

  # DELETE /api/v1/ssp_documents/:ssp_document_id/roles/:id
  def destroy
    role = find_role!
    return if performed?

    # Removing a role that statements still reference would manufacture exactly
    # the dangling reference this issue exists to remove.
    referencing = statements_referencing(role["id"])
    if referencing.any?
      return render_api_error(
        "role #{role['id'].inspect} is still referenced by #{referencing.size} statement(s); " \
        "reassign them first", status: :conflict
      )
    end

    write_roles(@ssp_document.declared_roles.reject { |r| r["id"] == role["id"] })
    audit_log("ssp_role_undeclared", subject: @ssp_document, metadata: { role_id: role["id"] })

    head :no_content
  end

  private

  def create_from_membership_role(membership_role)
    role = @ssp_document.declare_responsible_membership_role(membership_role)
    @ssp_document.save!
    audit_log("ssp_role_declared", subject: @ssp_document,
                                   metadata: { role_id: role["id"], membership_role: membership_role })

    render json: { data: serialize(role) }, status: :created
  rescue OscalRole::DeclarationError => e
    render_api_error("#{e.message}; see meta.membership_roles")
  end

  def set_ssp_document
    # By slug, matching Api::V1::SspComponentsController.
    @ssp_document = SspDocument.find_by!(slug: params[:ssp_document_id])
  end

  def render_api_error(message, status: :unprocessable_content)
    render json: { error: message }, status: status
  end

  # A role belongs to its SSP, so the authorization question is about the SSP —
  # the same boundary-scoped check the components controller makes, including
  # the #952 rule that a nil boundary is not "open to everyone".
  def authorize_read!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("ssp.read",
                                           authorization_boundary_id: @ssp_document.authorization_boundary_id)

    raise NotAuthorizedError, "Not authorized to view this system security plan"
  end

  def authorize_write!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("ssp.write",
                                           authorization_boundary_id: @ssp_document.authorization_boundary_id)

    raise NotAuthorizedError, "Not authorized to modify this system security plan"
  end

  def find_role!
    role = @ssp_document.declared_roles.find { |r| r["id"] == params[:id] }
    render_api_error("role #{params[:id].inspect} is not declared on this document", status: :not_found) if role.nil?
    role
  end

  def write_roles(roles)
    @ssp_document.oscal_roles = roles
    @ssp_document.save!
  end

  def statements_referencing(role_id)
    SspControlStatement.joins(ssp_control: :ssp_document)
                       .where(ssp_documents: { id: @ssp_document.id })
                       .select { |s| Array(s.responsible_roles_data).any? { |r| r["role-id"] == role_id } }
  end

  def serialize(role)
    {
      id: role["id"],
      title: role["title"],
      organization_defined: OscalRole.organization_defined?(role),
      nist_suggested: OscalRole.suggested_ids.include?(role["id"])
    }
  end

  def role_params
    params.fetch(:role, {}).permit(:id, :title, :organization_defined, :membership_role)
  end
end
