# REST API for evidence ↔ control associations (#756).
#
# An EvidenceControlLink ties a piece of evidence to a specific control
# (e.g. "AC-2"), optionally scoped to the document that control lives in
# (SSP / SAR / SAP / CDEF / POA&M).
#
# The document scoping is what drives OSCAL output: when a link carries
# document_type + document_id, EvidenceControlLink's after_create hook
# creates a managed BackMatterResource on that document, which
# BackMatterBuilder emits into the document's OSCAL back-matter with the
# evidence's durable resolver href (#680). The web UI never sets those
# two fields, so back-matter linkage was previously unreachable — this
# API is the first surface that can establish it.
#
# Endpoints:
#   GET    /api/v1/evidences/:evidence_id/control_links      — list
#   POST   /api/v1/evidences/:evidence_id/control_links      — link a control
#   DELETE /api/v1/evidences/:evidence_id/control_links/:id  — unlink
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (evidence.read / evidence.write RBAC)
#   AU-12 Audit Record Generation (mutations logged)
#   CA-2 Security Assessment (evidence-to-control traceability)
#   CM-8 System Component Inventory (back-matter resource provenance)
#
class Api::V1::EvidenceControlLinksController < Api::V1::BaseController
  before_action :set_evidence
  before_action :set_control_link, only: %i[destroy]
  before_action :authorize_read!, only: %i[index]
  before_action :authorize_write!, only: %i[create destroy]

  # GET /api/v1/evidences/:evidence_id/control_links
  def index
    scope = @evidence.evidence_control_links.order(created_at: :desc)

    result = paginate(scope)
    render json: {
      data: result[:data].map { |link| serialize(link) },
      meta: result[:meta]
    }
  end

  # POST /api/v1/evidences/:evidence_id/control_links
  def create
    link = @evidence.evidence_control_links.build(control_link_params)

    unless valid_document_type?(link.document_type)
      return render json: {
        error: "Validation failed",
        details: [ "document_type must be one of: #{EvidenceControlLink::DOCUMENT_TYPES.join(', ')}" ]
      }, status: :unprocessable_entity
    end

    if link.save
      audit_log("evidence_control_link_created", subject: @evidence,
                metadata: { control_id: link.control_id, document_type: link.document_type,
                            document_id: link.document_id })
      render json: { data: serialize(link, detailed: true) }, status: :created
    else
      render json: { error: "Validation failed", details: link.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/evidences/:evidence_id/control_links/:id
  def destroy
    audit_log("evidence_control_link_deleted", subject: @evidence,
              metadata: { control_id: @control_link.control_id,
                          document_type: @control_link.document_type,
                          document_id: @control_link.document_id })
    @control_link.destroy
    head :no_content
  end

  private

  def set_evidence
    key = params[:evidence_id]
    @evidence =
      if key.to_s.match?(/\A\d+\z/)
        Evidence.find(key)
      else
        Evidence.find_by!(slug: key)
      end
  end

  def set_control_link
    @control_link = @evidence.evidence_control_links.find(params[:id])
  end

  # document_type is optional (a bare control link carries no document),
  # but when present it must name a real OSCAL document class — otherwise
  # `document_type.constantize` in the model would raise on an arbitrary
  # client-supplied string.
  def valid_document_type?(document_type)
    document_type.blank? || EvidenceControlLink::DOCUMENT_TYPES.include?(document_type)
  end

  def control_link_params
    params.require(:control_link).permit(:control_id, :control_type, :document_type, :document_id)
  end

  def serialize(link, detailed: false)
    data = {
      id: link.id,
      evidence_id: link.evidence_id,
      control_id: link.control_id,
      control_type: link.control_type,
      document_type: link.document_type,
      document_id: link.document_id,
      created_at: link.created_at.utc.iso8601
    }

    if detailed
      resource = BackMatterResource.find_by(evidence: @evidence, uuid: @evidence.uuid)
      data[:back_matter_resource_uuid] = resource&.uuid
      data[:oscal_href] = resource&.href
    end

    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read")

    raise NotAuthorizedError, "Not authorized to view evidence control links"
  end

  def authorize_write!
    return if current_user.admin?

    boundary_id = @evidence&.authorization_boundary_id
    return if current_user.has_permission?("evidence.write", authorization_boundary_id: boundary_id)

    raise NotAuthorizedError, "Not authorized to modify evidence control links"
  end
end
