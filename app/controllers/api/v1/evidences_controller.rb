# REST API for compliance evidence artifacts (#756).
#
# Evidence is the raw material of an assessment: a screenshot, scan
# result, config export, signed statement, or policy document that
# demonstrates a control is implemented. Until now evidence could only
# be created through the web UI (`EvidencesController`) — the API
# exposed attestations nested under an *assumed-existing* evidence but
# offered no way to create one, blocking SaaS tenants without automated
# validation pipelines from submitting evidence programmatically.
#
# This controller closes that gap per the SPARC api-first rule.
#
# Endpoints:
#   GET    /api/v1/evidences            — list (paginated, boundary-scoped)
#   GET    /api/v1/evidences/:id        — show (id or slug)
#   POST   /api/v1/evidences            — create (multipart: file + metadata)
#   PATCH  /api/v1/evidences/:id        — update
#   DELETE /api/v1/evidences/:id        — delete (audit-logged)
#
# Control/CDEF association lives in Api::V1::EvidenceControlLinksController
# (`/api/v1/evidences/:evidence_id/control_links`), which is what drives
# OSCAL back-matter emission.
#
# Upload validation: evidence is arbitrary artifact content (PDF, PNG,
# logs, archives), so unlike the document-import path there is no MIME
# allowlist. Defense is the executable-signature deny-list shared with
# FileUploadable (#509) plus the model-level size cap
# (AttachmentSizeLimit → 422), per the #756 design decision.
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (evidence.read / evidence.write RBAC, boundary-scoped)
#   AC-6 Least Privilege (non-admin sees only their boundaries + global evidence)
#   AU-10 Non-repudiation (server-stamped collected_at / collected_by — never client-supplied)
#   AU-12 Audit Record Generation (mutations logged)
#   CA-2 / CA-7 Security Assessment & Continuous Monitoring (evidence lifecycle)
#   SI-10 Information Input Validation (executable-signature deny-list, size cap)
#
class Api::V1::EvidencesController < Api::V1::BaseController
  before_action :set_evidence, only: %i[show update destroy]
  before_action :authorize_read!, only: %i[index show]
  before_action :authorize_write!, only: %i[create update destroy]

  # GET /api/v1/evidences
  def index
    scope = apply_filters(scoped_evidences)

    result = paginate(scope)
    render json: {
      data: result[:data].map { |e| serialize(e) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/evidences/:id
  def show
    render json: { data: serialize(@evidence, detailed: true) }
  end

  # POST /api/v1/evidences
  #
  # Accepts multipart/form-data (evidence[file] + metadata) or plain JSON
  # for metadata-only evidence.
  def create
    reject_if_executable_signature!(uploaded_file) if uploaded_file

    evidence = Evidence.new(evidence_params)
    # #738 / AU-10: provenance is system-recorded, never client-supplied.
    evidence.collected_at = Time.current.utc
    evidence.collected_by = current_user&.display_name.presence || current_user&.email

    if evidence.save
      evidence.compute_file_hash! if evidence.file.attached?
      sync_control_links(evidence)
      audit_log("evidence_created", subject: evidence, metadata: { title: evidence.title })
      render json: { data: serialize(evidence, detailed: true) }, status: :created,
             location: api_v1_evidence_url(evidence.slug)
    else
      render json: { error: "Validation failed", details: evidence.errors.full_messages },
             status: :unprocessable_entity
    end
  rescue FileUploadable::UploadRejectedError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /api/v1/evidences/:id
  def update
    reject_if_executable_signature!(uploaded_file) if uploaded_file

    if @evidence.update(evidence_params)
      # Re-hash only when a new blob arrived (mirrors the web controller).
      @evidence.compute_file_hash! if @evidence.file.attached? && @evidence.file_hash.blank?
      sync_control_links(@evidence)
      audit_log("evidence_updated", subject: @evidence, metadata: { title: @evidence.title })
      render json: { data: serialize(@evidence, detailed: true) }
    else
      render json: { error: "Validation failed", details: @evidence.errors.full_messages },
             status: :unprocessable_entity
    end
  rescue FileUploadable::UploadRejectedError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/evidences/:id
  def destroy
    audit_log("evidence_deleted", subject: @evidence, metadata: { title: @evidence.title })
    @evidence.destroy
    render json: { data: { id: @evidence.id, slug: @evidence.slug, deleted: true } }
  end

  private

  # Accept either numeric id or slug — the UI route uses slug; API
  # callers commonly use numeric id. Mirrors AttestationsController.
  def set_evidence
    key = params[:id]
    @evidence =
      if key.to_s.match?(/\A\d+\z/)
        Evidence.find(key)
      else
        Evidence.find_by!(slug: key)
      end
  end

  # Boundary-scoped index. Unlike DocumentBaseController, nil-boundary
  # (global) evidence IS included for non-admins — evidence boundary is
  # optional and global artifacts are visible to all authenticated users
  # in the UI (BoundaryScopedDocument). Keeping API and UI in agreement
  # avoids the API hiding records the same user can see on screen.
  def scoped_evidences
    scope = if current_user.admin?
      Evidence.all
    else
      boundary_ids = current_user.authorization_boundaries.ids + [ nil ]
      Evidence.where(authorization_boundary_id: boundary_ids)
    end
    scope.order(created_at: :desc)
  end

  def apply_filters(scope)
    scope = scope.where(evidence_type: params[:type]) if params[:type].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    if params[:authorization_boundary_id].present?
      scope = scope.where(authorization_boundary_id: params[:authorization_boundary_id])
    end
    if params[:control_id].present?
      linked = EvidenceControlLink.where(control_id: params[:control_id]).select(:evidence_id)
      scope = scope.where(id: linked)
    end
    if params[:q].present?
      term = "%#{params[:q]}%"
      scope = scope.where(
        "title ILIKE :t OR description ILIKE :t OR original_filename ILIKE :t", t: term
      )
    end
    scope
  end

  def uploaded_file
    params.dig(:evidence, :file).presence
  end

  # #509 deny-list, shared with FileUploadable so the signature table has
  # a single home. The web concern's variant renders/redirects; API
  # callers get a 422 JSON envelope instead.
  def reject_if_executable_signature!(file)
    return unless file.respond_to?(:path)

    header = File.binread(file.path, 32).to_s
    FileUploadable::EXECUTABLE_MAGIC_BYTES.each do |signature, description|
      next unless header.start_with?(signature)

      raise FileUploadable::UploadRejectedError,
            "File rejected: detected #{description}. Executable content is not permitted as an upload."
    end
  end

  # Accepts either an array (`control_ids[]=AC-1&control_ids[]=AC-2`) or
  # the comma-separated string the web form posts. Absent key ⇒ leave
  # existing links untouched; present-but-empty ⇒ clear them.
  def sync_control_links(evidence)
    raw = params.dig(:evidence, :control_ids)
    return if raw.nil?

    control_ids = (raw.is_a?(Array) ? raw : raw.to_s.split(",")).map { |c| c.to_s.strip }.reject(&:blank?)

    evidence.evidence_control_links.destroy_all
    control_ids.each { |cid| evidence.evidence_control_links.create!(control_id: cid) }
  end

  def evidence_params
    # collected_at / collected_by are server-stamped on create (#738),
    # never user-supplied.
    params.require(:evidence).permit(
      :title, :description, :evidence_type, :status,
      :source, :authorization_boundary_id, :file
    )
  end

  def serialize(evidence, detailed: false)
    data = {
      id: evidence.id,
      uuid: evidence.uuid,
      slug: evidence.slug,
      title: evidence.title,
      evidence_type: evidence.evidence_type,
      type_label: evidence.type_label,
      status: evidence.status,
      status_label: evidence.status_label,
      source: evidence.source,
      authorization_boundary_id: evidence.authorization_boundary_id,
      collected_at: evidence.collected_at&.utc&.iso8601,
      collected_by: evidence.collected_by,
      has_file: evidence.file.attached?,
      created_at: evidence.created_at.utc.iso8601
    }

    if detailed
      data[:description] = evidence.description
      data[:original_filename] = evidence.original_filename
      data[:file_content_type] = evidence.file_content_type
      data[:file_size] = evidence.file_size
      data[:file_hash] = evidence.file_hash
      data[:oscal_resolver_url] = evidence.oscal_resolver_url
      data[:linked_control_ids] = evidence.linked_control_ids
      data[:attested] = evidence.attested?
      data[:updated_at] = evidence.updated_at.utc.iso8601
    end

    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read")

    raise NotAuthorizedError, "Not authorized to view evidence"
  end

  def authorize_write!
    return if current_user.admin?

    boundary_id = @evidence&.authorization_boundary_id || params.dig(:evidence, :authorization_boundary_id)
    return if current_user.has_permission?("evidence.write", authorization_boundary_id: boundary_id)

    raise NotAuthorizedError, "Not authorized to modify evidence"
  end
end
