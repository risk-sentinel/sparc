# REST API for the components of a System Security Plan.
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# SSP components had NO Api::V1 surface at all. They could be created, edited
# and deleted only through the enrichment screen, which makes the web UI the
# only way to perform those mutations — the one thing the API-first rule exists
# to prevent. Found while adding validation modeling (#998): a validation
# component records a FIPS 140-2 certificate and the product it validates, and
# that is exactly the kind of assertion an integrator needs to write from a
# pipeline rather than by hand in a browser.
#
# The gap was not visible from the endpoint inventory, because an endpoint that
# was never written cannot appear in a list of endpoints that answer wrongly.
# That is the shape #995 is about.
#
# Endpoints (nested under /api/v1/ssp_documents/:ssp_document_id):
#   GET    .../components        — list this SSP's components
#   GET    .../components/:id    — one component, with its validation pairing
#   POST   .../components        — create
#   PATCH  .../components/:id    — update
#   DELETE .../components/:id    — delete
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (boundary-scoped ssp.read / ssp.write)
#   AU-12 Audit Record Generation (every mutation logged)
#   SI-10 Information Input Validation (the model refuses a validation claim on
#         a component that is not a validation, or one pointing at another SSP)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::SspComponentsController < Api::V1::BaseController
  before_action :set_ssp_document
  before_action :set_component, only: %i[show update destroy]
  before_action :authorize_read!, only: %i[index show]
  before_action :authorize_write!, only: %i[create update destroy]

  # GET /api/v1/ssp_documents/:ssp_document_id/components
  def index
    scope = @ssp_document.ssp_components.order(:title)
    scope = scope.where(component_type: params[:component_type]) if params[:component_type].present?

    result = paginate(scope)
    result[:data] = result[:data].map { |component| serialize(component) }
    render json: result
  end

  # GET /api/v1/ssp_documents/:ssp_document_id/components/:id
  def show
    render json: { data: serialize(@component, detailed: true) }
  end

  # POST /api/v1/ssp_documents/:ssp_document_id/components
  def create
    component = @ssp_document.ssp_components.new(component_params)
    component.uuid = component_params[:uuid].presence || SecureRandom.uuid
    component.save!

    audit_log("ssp_component_created", subject: component,
              metadata: audit_metadata(component))

    render json: { data: serialize(component, detailed: true) }, status: :created
  end

  # PATCH /api/v1/ssp_documents/:ssp_document_id/components/:id
  def update
    @component.update!(component_params)

    audit_log("ssp_component_updated", subject: @component,
              metadata: audit_metadata(@component))

    render json: { data: serialize(@component, detailed: true) }
  end

  # DELETE /api/v1/ssp_documents/:ssp_document_id/components/:id
  #
  # `this-system` is refused. OSCAL requires the SSP to describe the system
  # itself, and the enrichment screen protects that component from its own sync
  # for the same reason; an API that could delete it would leave a document
  # that cannot be exported and no obvious way back.
  def destroy
    if @component.component_type == "this-system"
      return render json: {
        error: "The `this-system` component describes the system itself and cannot be deleted. " \
               "Change its title or description instead."
      }, status: :unprocessable_entity
    end

    metadata = audit_metadata(@component)
    @component.destroy!
    audit_log("ssp_component_deleted", subject: @ssp_document, metadata: metadata)

    head :no_content
  end

  private

  def set_ssp_document
    @ssp_document = SspDocument.find_by!(slug: params[:ssp_document_id])
  end

  def set_component
    # By uuid or by id: the uuid is what an OSCAL document carries and what a
    # pipeline holds, and the numeric id is what a UI-shaped caller has.
    id = params[:id].to_s
    @component = if id.match?(/\A\d+\z/)
      @ssp_document.ssp_components.find_by!(id: id)
    else
      @ssp_document.ssp_components.find_by!(uuid: id)
    end
  end

  # A component belongs to its SSP, so the authorization question is about the
  # SSP — the same boundary-scoped check Api::V1::SspDocumentsController makes,
  # including the #952 rule that a nil boundary is not "open to everyone".
  def authorize_read!
    return if current_user.admin?

    boundary_id = @ssp_document.authorization_boundary_id
    return if current_user.has_permission?("ssp.read", authorization_boundary_id: boundary_id)

    raise NotAuthorizedError, "Not authorized to view this system security plan"
  end

  def authorize_write!
    return if current_user.admin?

    boundary_id = @ssp_document.authorization_boundary_id
    return if current_user.has_permission?("ssp.write", authorization_boundary_id: boundary_id)

    raise NotAuthorizedError, "Not authorized to modify this system security plan"
  end

  def component_params
    permit_strictly(:ssp_component,
      :uuid, :component_type, :title, :description, :purpose,
      :status_state, :status_remarks, :remarks,
      # #998 — the validation pair. The model refuses these where they would
      # mean nothing, so a caller gets 422 naming the reason rather than a
      # stored value no exporter reads.
      :validation_type, :validation_reference, :validation_details_href,
      :validates_component_id,
      props_data: [ :name, :value, :class, :ns, :remarks ],
      links_data: [ :href, :rel, :"media-type", :text ],
      responsible_roles_data: [ :"role-id", { "party-uuids": [] } ],
      protocols_data: [ :uuid, :name, :title ]
    )
  end

  def audit_metadata(component)
    {
      ssp_document_id: @ssp_document.id,
      uuid: component.uuid,
      title: component.title,
      component_type: component.component_type
    }
  end

  def serialize(component, detailed: false)
    data = {
      id: component.id,
      uuid: component.uuid,
      component_type: component.component_type,
      title: component.title,
      description: component.description,
      purpose: component.purpose,
      status_state: component.status_state,
      cdef_document_id: component.cdef_document_id,
      created_at: component.created_at,
      updated_at: component.updated_at
    }

    # #998 — reported for a validation component even when empty, so a caller
    # can tell "this validation asserts nothing yet" from "this is not a
    # validation". A silently absent key would not distinguish them.
    if component.validation?
      data[:validation] = {
        validation_type: component.validation_type,
        validation_reference: component.validation_reference,
        validation_details_href: component.validation_details_href,
        validates_component_id: component.validates_component_id,
        validates_component_uuid: component.validated_component&.uuid
      }
    end

    return data unless detailed

    data.merge(
      status_remarks: component.status_remarks,
      remarks: component.remarks,
      props: component.props_data,
      links: component.links_data,
      responsible_roles: component.responsible_roles_data,
      protocols: component.protocols_data,
      # The other side of the pairing: what this component is validated BY.
      validated_by: component.validations.map { |v| { id: v.id, uuid: v.uuid, title: v.title } }
    )
  end
end
