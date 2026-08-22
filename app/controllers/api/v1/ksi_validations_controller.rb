# REST API for KSI validation tracking within an authorization boundary.
#
# All endpoints require Bearer token authentication.
#
# #1024 — reads require `evidence.read`, writes require `evidence.write` SCOPED
# TO THE BOUNDARY, and DELETE remains admin-only. Until then create and update
# required nothing beyond a valid token, on ANY boundary: `set_boundary` looked
# the boundary up without ever checking the caller against it, so any
# authenticated user could mark an indicator `passed` on a system they had no
# relationship with, and the audit event recorded it as a legitimate assessment.
#
# It reuses the evidence permissions rather than introducing `ksi.*` keys: a KSI
# validation IS assessment evidence, and anyone entitled to record evidence on a
# boundary is entitled to record a validation on it. That also avoids a
# migration in which every non-admin loses access until new grants are seeded.
#
# All mutations create audit events via audit_log().
#
# GET    /api/v1/authorization_boundaries/:id/ksi_validations           — list
# GET    /api/v1/authorization_boundaries/:id/ksi_validations/summary   — dashboard data
# GET    /api/v1/authorization_boundaries/:id/ksi_validations/export    — full export
# GET    /api/v1/authorization_boundaries/:id/ksi_validations/:id       — show
# POST   /api/v1/authorization_boundaries/:id/ksi_validations           — create
# PATCH  /api/v1/authorization_boundaries/:id/ksi_validations/:id       — update
# DELETE /api/v1/authorization_boundaries/:id/ksi_validations/:id       — delete (admin)
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (evidence.read / evidence.write, scoped to the
#     boundary — the CALLER is checked against it, not only the record)
#   AC-6 Least Privilege (admin-only delete; write requires a boundary grant)
#   AU-12 Audit Record Generation (mutations logged via audit_log)
#   CA-2 Assessment (KSI validation tracking)
#   CA-7 Continuous Monitoring (validation scheduling)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::KsiValidationsController < Api::V1::BaseController
  before_action :set_boundary
  before_action :set_validation, only: [ :show, :update, :destroy ]
  before_action :authorize_ksi_read!,  only: %i[index show summary export]
  before_action :authorize_ksi_write!, only: %i[create update]
  before_action :authorize_admin!, only: [ :destroy ]

  # GET /api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations
  def index
    scope = @boundary.ksi_validations
                     .includes(catalog_control: :control_family, evidence: [])
                     .order("control_families.sort_order", "catalog_controls.sort_id")

    scope = scope.by_status(params[:status]) if params[:status].present?
    scope = scope.by_theme(params[:theme]) if params[:theme].present?
    scope = scope.overdue if params[:overdue] == "true"

    result = paginate(scope)
    render json: {
      data: result[:data].map { |v| serialize_validation(v) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id
  def show
    render json: { data: serialize_validation(@validation, detailed: true) }
  end

  # POST /api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations
  def create
    validation = @boundary.ksi_validations.new(validation_params)
    validation.save!

    audit_log("ksi_validation_created", subject: validation,
      metadata: { ksi_id: validation.ksi_id, status: validation.status })

    render json: { data: serialize_validation(validation) }, status: :created
  end

  # PATCH /api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id
  def update
    @validation.update!(validation_params)

    audit_log("ksi_validation_updated", subject: @validation,
      metadata: { ksi_id: @validation.ksi_id, status: @validation.status })

    render json: { data: serialize_validation(@validation) }
  end

  # DELETE /api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id
  def destroy
    ksi_id = @validation.ksi_id
    @validation.destroy!

    audit_log("ksi_validation_deleted", subject: @validation,
      metadata: { ksi_id: ksi_id })

    render json: { data: { id: @validation.id, deleted: true } }
  end

  # GET /api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/summary
  def summary
    service = KsiExportService.new(@boundary)
    render json: { data: service.summary }
  end

  # GET /api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/export
  def export
    format = (params[:format].presence || "json").to_sym
    service = KsiExportService.new(@boundary)

    content_type = case format
    when :yaml then "application/x-yaml"
    when :xml  then "application/xml"
    else "application/json"
    end

    render plain: service.export(format: format), content_type: content_type
  end

  private

  # #574 — accept either numeric id or slug. Same rationale as #566
  # for control_catalogs / control_mappings: callers that build nested
  # URLs from the `id` returned by the parent create shouldn't 404.
  # #1024 — mirrors Api::V1::EvidencesController. Instance admins bypass; every
  # other caller needs the grant ON THIS BOUNDARY.
  def authorize_ksi_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read",
                                           authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view KSI validations for this boundary"
  end

  def authorize_ksi_write!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.write",
                                           authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to record KSI validations for this boundary"
  end

  def set_boundary
    id_or_slug = params[:authorization_boundary_id].to_s
    @boundary = if id_or_slug.match?(/\A\d+\z/)
      AuthorizationBoundary.find_by!(id: id_or_slug)
    else
      AuthorizationBoundary.find_by!(slug: id_or_slug)
    end
  end

  def set_validation
    @validation = @boundary.ksi_validations.find(params[:id])
  end

  # CodeQL `rb/insecure-mass-assignment` (alerts #19, #20) flags the trailing
  # `validation_metadata: {}`. The allow-list is explicit; what the rule cannot
  # distinguish is permitting an arbitrary nested HASH from permitting
  # arbitrary model ATTRIBUTES. `validation_metadata` is a jsonb column, so the
  # open hash is stored as a document and can never reach an attribute writer.
  #
  # `evidence_id` is a real foreign key and IS a live authorization surface —
  # see #851, where the model now validates that the referenced Evidence
  # belongs to this boundary. Left mass-assignable deliberately: the guard
  # belongs on the model so every writer is covered, not on this one call site.
  def validation_params
    permit_strictly(:ksi_validation,
      :catalog_control_id, :evidence_id, :status, :validation_method,
      :evidence_format, :last_validated_at, :next_validation_due,
      :notes, validation_metadata: {}
    )
  end

  def serialize_validation(validation, detailed: false)
    data = {
      id: validation.id,
      uuid: validation.uuid,
      ksi_id: validation.ksi_id,
      ksi_title: validation.ksi_title,
      theme_code: validation.theme_code,
      theme_name: validation.theme_name,
      status: validation.status,
      validation_method: validation.validation_method,
      last_validated_at: validation.last_validated_at&.iso8601,
      next_validation_due: validation.next_validation_due&.iso8601,
      overdue: validation.expired?,
      created_at: validation.created_at.iso8601,
      updated_at: validation.updated_at.iso8601
    }

    if detailed
      data[:evidence_format] = validation.evidence_format
      data[:notes] = validation.notes
      data[:validation_metadata] = validation.validation_metadata
      data[:evidence] = validation.evidence ? {
        id: validation.evidence.id,
        title: validation.evidence.title,
        evidence_type: validation.evidence.evidence_type,
        status: validation.evidence.status,
        file_hash: validation.evidence.file_hash
      } : nil
    end

    data
  end
end
