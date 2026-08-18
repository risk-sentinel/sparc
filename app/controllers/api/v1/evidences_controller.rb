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
#   AU-10 Non-repudiation (server-stamped collected_at / collected_by / collected_by_user_id
#         — never client-supplied; a token's submission is attributed to the token's account)
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
    EvidenceUploadPolicy.validate!(uploaded_file)

    evidence = Evidence.new(evidence_params)
    # #738 / #934 / AU-10: provenance is system-recorded, never client-supplied.
    #
    # `current_user` here is the token's owner — for a `sparc_sa_…` token that is
    # the service-account User itself (ApiAuthentication#authenticate_sparc_token!),
    # so evidence submitted by automation is attributed to the account that
    # submitted it rather than to the human who owns that account.
    evidence.stamp_collection!(actor: current_user)
    # #947 — links are BUILT before the first save, not created after it.
    # `compute_file_hash!` calls `save!`, so with links still created afterwards
    # that save would re-validate a record with no links and raise on every
    # upload carrying a file, now that at least one link is required.
    build_control_links(evidence)

    if evidence.save
      evidence.compute_file_hash! if evidence.file.attached?
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
    EvidenceUploadPolicy.validate!(uploaded_file)

    @evidence.assign_attributes(evidence_params)
    build_control_links(@evidence)

    if @evidence.save
      # Re-hash only when a new blob arrived (mirrors the web controller).
      @evidence.compute_file_hash! if @evidence.file.attached? && @evidence.file_hash.blank?
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

  # #908 — the same query object the evidence index screen uses. This method
  # and the controller's web counterpart were separate implementations of the
  # same four filters, which is exactly how `source` came to be filterable on
  # neither surface despite being a column on both.
  def apply_filters(scope)
    EvidenceBrowseQuery.new(params, scope: scope).records
  end

  def uploaded_file
    params.dig(:evidence, :file).presence
  end

  # #868 — the executable-signature deny-list used to live here as a local copy
  # of FileUploadable's. It now lives in EvidenceUploadPolicy alongside the
  # extension allowlist and the declared-vs-actual type check, so the UI and the
  # API enforce one policy rather than two that drift. This controller keeps its
  # `rescue FileUploadable::UploadRejectedError` — EvidenceUploadPolicy::Error
  # is that same class — so API callers still get a 422 JSON envelope.

  # Accepts either an array (`control_ids[]=AC-1&control_ids[]=AC-2`) or
  # the comma-separated string the web form posts. Absent key ⇒ leave
  # existing links untouched; present-but-empty ⇒ clear them.
  # #947 — replaces `sync_control_links`, which ran AFTER the save. Mirrors
  # EvidencesController#build_control_links so the two surfaces cannot diverge
  # on a rule the model now enforces for both.
  def build_control_links(evidence)
    raw = params.dig(:evidence, :control_ids)
    return if raw.nil?

    control_ids = (raw.is_a?(Array) ? raw : raw.to_s.split(",")).map { |c| c.to_s.strip }.reject(&:blank?)

    # Marked for destruction rather than destroyed outright, so a rejected save
    # leaves the existing links intact instead of stripping them anyway.
    evidence.evidence_control_links.each do |link|
      link.mark_for_destruction unless control_ids.include?(link.control_id)
    end

    existing = evidence.evidence_control_links.reject(&:marked_for_destruction?).map(&:control_id)
    (control_ids - existing).each { |cid| evidence.evidence_control_links.build(control_id: cid) }
  end

  def evidence_params
    # collected_at / collected_by are server-stamped on create (#738),
    # never user-supplied.
    # #947 — attestations nest here too, so the API can record a fileless
    # attestation in one call exactly as the UI does. `attester_name` /
    # `attester_email` are absent deliberately: they are the snapshot the model
    # takes from the resolved account (#934), not client input.
    params.require(:evidence).permit(
      :title, :description, :evidence_type, :status,
      :source, :authorization_boundary_id, :file,
      attestations_attributes: [ :id, :attester_user_id, :role, :statement,
                                 :attested_at, :frequency, :status ]
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
      # #934 — the account, alongside the historical name. Null where the row
      # predates the backfill's ability to resolve it unambiguously.
      collected_by_user_id: evidence.collected_by_user_id,
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
