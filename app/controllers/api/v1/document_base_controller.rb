# Base controller for boundary-scoped document API endpoints.
#
# Provides shared CRUD actions, boundary-scoped authorization,
# pagination, filtering, and audit logging for document resources
# (SSP, SAR, SAP, POA&M).
#
# Subclasses must override:
#   document_class          — the ActiveRecord model (e.g., SspDocument)
#   document_param_key      — the strong params root key (e.g., :ssp_document)
#   read_permission_key     — e.g., "ssp.read"
#   write_permission_key    — e.g., "ssp.write"
#   document_params         — permitted params for create/update
#   serialize_document(doc, detailed:) — JSON serialization
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (boundary-scoped authorization)
#   AC-6 Least Privilege (non-admin sees only their boundaries)
#   AU-12 Audit Record Generation (mutations logged via audit_log)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::DocumentBaseController < Api::V1::BaseController
  before_action :set_document, only: [ :show, :update, :destroy ]
  before_action :authorize_document_read!, only: [ :show ]
  before_action :authorize_document_write!, only: [ :create, :update, :destroy ]

  # GET /api/v1/{resource}
  def index
    scope = scoped_documents
    scope = apply_filters(scope)

    result = paginate(scope)
    render json: {
      data: result[:data].map { |doc| serialize_document(doc) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/{resource}/:id
  def show
    render json: { data: serialize_document(@document, detailed: true) }
  end

  # POST /api/v1/{resource}
  def create
    doc = document_class.new(document_params)
    doc.save!

    audit_log("#{document_audit_name}_created", subject: doc, metadata: { name: doc.name })
    render json: { data: serialize_document(doc) }, status: :created,
           location: url_for([ :api, :v1, doc ])
  end

  # PUT /api/v1/{resource}/:id
  def update
    @document.update!(document_params)

    audit_log("#{document_audit_name}_updated", subject: @document, metadata: { name: @document.name })
    render json: { data: serialize_document(@document) }
  end

  # DELETE /api/v1/{resource}/:id
  def destroy
    @document.soft_delete!

    audit_log("#{document_audit_name}_deleted", subject: @document, metadata: { name: @document.name })
    render json: { data: { id: @document.id, slug: @document.slug, deleted: true } }
  end

  private

  # --- Subclass hooks (must override) ---

  def document_class
    raise NotImplementedError
  end

  def document_param_key
    raise NotImplementedError
  end

  def read_permission_key
    raise NotImplementedError
  end

  def write_permission_key
    raise NotImplementedError
  end

  def document_params
    raise NotImplementedError
  end

  def serialize_document(_doc, detailed: false)
    raise NotImplementedError
  end

  # --- Shared helpers ---

  def document_audit_name
    document_class.name.underscore
  end

  # Boundary-scoped index: admin sees all, non-admin sees only their boundaries
  def scoped_documents
    scope = if current_user.admin?
      document_class.all
    else
      boundary_ids = current_user.authorization_boundaries.pluck(:id)
      document_class.where(authorization_boundary_id: boundary_ids)
    end
    scope.order(created_at: :desc)
  end

  def apply_filters(scope)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    scope = scope.where(authorization_boundary_id: params[:authorization_boundary_id]) if params[:authorization_boundary_id].present?
    scope
  end

  def set_document
    @document = document_class.find_by!(slug: params[:id])
  end

  def authorize_document_read!
    return if current_user.admin?
    return if @document.authorization_boundary_id.nil?
    return if current_user.has_permission?(read_permission_key, authorization_boundary_id: @document.authorization_boundary_id)

    raise NotAuthorizedError, "Not authorized to view this #{document_class.model_name.human.downcase}"
  end

  def authorize_document_write!
    return if current_user.admin?

    boundary_id = @document&.authorization_boundary_id || params.dig(document_param_key, :authorization_boundary_id)
    return if current_user.has_permission?(write_permission_key, authorization_boundary_id: boundary_id)

    raise NotAuthorizedError, "Not authorized to modify this #{document_class.model_name.human.downcase}"
  end
end
