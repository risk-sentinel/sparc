# REST API for control families within a catalog (#895).
#
# First slice of the Catalog API. The catalog container had a full API while its
# CONTENTS had none — you could create a catalog over the API but not put a
# single family or control in it. The web UI has managed both all along, so this
# is the API catching up to a shipping UI, not new capability.
#
# Identifier decision (#881, recorded on #895): a catalog is addressable by
# **uuid, slug or numeric id** on read, via ControlCatalog.find_for_url. That is
# backwards-compatible with every link and script already in existence, and it
# matches the precedent set by Api::V1::EvidencesController ("accept either
# numeric id or slug"). Families are addressed by their CODE (`ac`), which is
# unique per catalog and is what control ids already encode.
#
# GET    /api/v1/control_catalogs/:id/control_families      — list
# GET    /api/v1/control_catalogs/:id/control_families/:id  — show
# POST   /api/v1/control_catalogs/:id/control_families      — create
# PATCH  /api/v1/control_catalogs/:id/control_families/:id  — update
# DELETE /api/v1/control_catalogs/:id/control_families/:id  — delete
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (catalog write permission gates every mutation)
#   AU-2 Audit Events (every mutation is audited)
#   CM-3 Configuration Change Control (catalog content changes are attributable)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::ControlFamiliesController < Api::V1::BaseController
  before_action :set_control_catalog
  before_action :authorize_catalog_write!, only: [ :create, :update, :destroy ]
  before_action :set_control_family, only: [ :show, :update, :destroy ]

  # GET /api/v1/control_catalogs/:control_catalog_id/control_families
  def index
    scope = @control_catalog.control_families.order(:sort_order, :code)
    scope = scope.where("LOWER(code) = ?", params[:code].to_s.downcase) if params[:code].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |f| serialize_family(f) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/control_catalogs/:control_catalog_id/control_families/:id
  def show
    render json: { data: serialize_family(@control_family, detailed: true) }
  end

  # POST /api/v1/control_catalogs/:control_catalog_id/control_families
  def create
    family = @control_catalog.control_families.new(family_params)
    family.save!

    audit_log("api_control_family_created", subject: family,
              metadata: { control_catalog_id: @control_catalog.id, code: family.code })
    render json: { data: serialize_family(family) }, status: :created
  end

  # PATCH /api/v1/control_catalogs/:control_catalog_id/control_families/:id
  def update
    @control_family.update!(family_params)

    audit_log("api_control_family_updated", subject: @control_family,
              metadata: { control_catalog_id: @control_catalog.id, code: @control_family.code })
    render json: { data: serialize_family(@control_family) }
  end

  # DELETE /api/v1/control_catalogs/:control_catalog_id/control_families/:id
  def destroy
    code = @control_family.code
    controls = @control_family.catalog_controls.count

    # Refuse rather than silently cascade: deleting a family takes its controls
    # with it, and a catalog's controls are referenced by SSP/SAP/SAR content.
    if controls.positive?
      return render json: {
        error: "Family #{code} still has #{controls} control(s). Delete them first."
      }, status: :unprocessable_entity
    end

    @control_family.destroy!
    audit_log("api_control_family_deleted", subject: @control_family,
              metadata: { control_catalog_id: @control_catalog.id, code: code })
    render json: { data: { code: code, deleted: true } }
  end

  private

  # #881/#895 — uuid, slug or numeric id. The uuid is the stable identity; the
  # others resolve so nothing already written against this API breaks.
  def set_control_catalog
    @control_catalog = ControlCatalog.find_for_url(params[:control_catalog_id]) ||
                       raise(ActiveRecord::RecordNotFound, "No catalog #{params[:control_catalog_id].inspect}")
  end

  # Addressed by code, scoped to the catalog — a bare code is ambiguous across
  # catalogs, and looking up by id would let an id from another catalog through.
  def set_control_family
    @control_family = @control_catalog.control_families
                                      .find_by("LOWER(code) = ?", params[:id].to_s.downcase) ||
                      raise(ActiveRecord::RecordNotFound, "No family #{params[:id].inspect} in this catalog")
  end

  def authorize_catalog_write!
    return if current_user.admin?
    return if current_user.has_permission?("catalogs.write")

    raise NotAuthorizedError, "Not authorized to modify catalog content"
  end

  # Enumerated deliberately. The web form posts a known set, but an API endpoint
  # accepting a loose hash would let arbitrary keys into a record the OSCAL
  # exporters read. Every field here is stated, and adding one is a decision.
  def family_params
    permit_strictly(:control_family, :code, :name, :description, :sort_order)
  end

  def serialize_family(family, detailed: false)
    data = {
      id: family.id,
      code: family.code,
      name: family.name,
      description: family.description,
      sort_order: family.sort_order,
      control_catalog_id: family.control_catalog_id,
      controls_count: family.catalog_controls.count,
      created_at: family.created_at.iso8601,
      updated_at: family.updated_at.iso8601
    }

    if detailed
      data[:control_catalog] = {
        id: @control_catalog.id,
        uuid: @control_catalog.oscal_uuid,
        name: @control_catalog.name
      }
    end

    data
  end
end
