class EvidencesController < ApplicationController
  include CollectionViewable
  include BoundaryScopedDocument
  boundary_scoped Evidence, read: "evidence.read", write: "evidence.write"

  before_action :set_evidence, only: [ :show, :edit, :update, :destroy ]
  # #738: boundary-scoped access. show = read; edit/update/destroy/create = write.
  before_action :authorize_document_read!, only: [ :show ]
  before_action :authorize_document_write!, only: [ :edit, :update, :destroy, :create ]

  # #888 — the facets this screen offers. The chrome that renders them is
  # shared; only the names and the scoping below are screen-specific.
  EVIDENCE_FACETS = %i[type status control_id authorization_boundary_id].freeze
  EVIDENCE_FACET_LABELS = {
    type: "Type", status: "Status", control_id: "Control",
    authorization_boundary_id: "Authorization boundary"
  }.freeze

  def index
    scope = boundary_scoped_relation(Evidence).order(created_at: :desc)
    @total_count = scope.count
    @link_count = EvidenceControlLink.where(evidence_id: boundary_scoped_relation(Evidence).select(:id)).count

    scope = scope.where(evidence_type: params[:type]) if params[:type].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(authorization_boundary_id: params[:authorization_boundary_id]) if params[:authorization_boundary_id].present?

    if params[:control_id].present?
      evidence_ids = EvidenceControlLink.where(control_id: ControlId.forms(params[:control_id]))
                                        .select(:evidence_id)
      scope = scope.where(id: evidence_ids)
    end

    # #888 — this screen searched on `search`, everything else on `q`. It reads
    # `q` now like the rest of the app; `search` still works so existing links
    # and bookmarks do not break.
    term = params[:q].presence || params[:search].presence
    if term.present?
      pattern = "%#{Evidence.sanitize_sql_like(term)}%"
      scope = scope.where(
        "title ILIKE :q OR description ILIKE :q OR original_filename ILIKE :q", q: pattern
      )
    end

    @facets = active_facets(EVIDENCE_FACETS, labels: EVIDENCE_FACET_LABELS)
    @clear_facets = clear_facets_params(EVIDENCE_FACETS)
    @view_mode = resolve_view_mode(:evidences)
    @pagy, @evidences = paginate_collection(scope)
  end

  def show
    @attestations = @evidence.attestations.order(attested_at: :desc)
    @control_links = @evidence.evidence_control_links.order(:control_id)
  end

  def new
    # #770 bug 5 — allow pre-scoping to a boundary so "Add Artifact" from the
    # Authorization Boundary screen lands on a form already tied to it.
    # #868 — evidence_type carries over from "Save and add another" so a run of
    # screenshots or exports keeps its type without re-selection.
    @evidence = Evidence.new(
      authorization_boundary_id: params[:authorization_boundary_id],
      evidence_type: params[:evidence_type]
    )
  end

  def create
    # #868: the same guard Api::V1 applies. Runs BEFORE the record is built so
    # a rejected file never reaches Active Storage.
    EvidenceUploadPolicy.validate!(uploaded_file)

    @evidence = Evidence.new(evidence_params)
    # #738: collection provenance is system-recorded (UTC, no DST drift), not self-asserted.
    @evidence.collected_at = Time.current.utc
    @evidence.collected_by = current_user&.display_name.presence || current_user&.email

    if @evidence.save
      audit_log("evidence_created", subject: @evidence, metadata: { title: @evidence.title })
      process_file_upload if @evidence.file.attached?
      sync_control_links

      # #902 — never report success for a file that is not there. If the user
      # chose a file and it did not end up attached, the record saved but the
      # artefact did not, and "uploaded successfully" would be a lie an
      # assessor might rely on.
      if file_posted_but_not_attached?
        redirect_to @evidence, flash: { error: missing_attachment_error(@evidence) }
      else
        redirect_to after_create_path(@evidence), flash: { success: upload_success_notice(@evidence) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  rescue EvidenceUploadPolicy::Error => e
    reject_upload(e, :new)
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  def update
    EvidenceUploadPolicy.validate!(uploaded_file)

    if @evidence.update(evidence_params)
      audit_log("evidence_updated", subject: @evidence, metadata: { title: @evidence.title })
      process_file_upload if @evidence.file.attached? && @evidence.file_hash.blank?
      sync_control_links

      if file_posted_but_not_attached?
        redirect_to @evidence, flash: { error: missing_attachment_error(@evidence) }
      else
        redirect_to @evidence, flash: { success: "Evidence updated successfully." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  rescue EvidenceUploadPolicy::Error => e
    reject_upload(e, :edit)
  end

  def destroy
    title = @evidence.title
    audit_log("evidence_deleted", subject: @evidence, metadata: { title: title })
    @evidence.destroy
    redirect_to evidences_path, flash: { success: "Evidence '#{title}' deleted." }
  end

  private

  def set_evidence
    @evidence = Evidence.find_by!(slug: params[:id])
  end

  def evidence_params
    # collected_at / collected_by are set by the server on create (#738), never user-supplied.
    params.require(:evidence).permit(
      :title, :description, :evidence_type, :status,
      :source, :authorization_boundary_id, :file
    )
  end

  def uploaded_file
    params.dig(:evidence, :file).presence
  end

  # #868 — "Save and add another" returns to the form rather than the show page,
  # carrying the boundary and type forward so a run of related artefacts does
  # not mean re-selecting them every time.
  def after_create_path(evidence)
    return evidence unless params[:commit_and_new].present?

    new_evidence_path(
      authorization_boundary_id: evidence.authorization_boundary_id,
      evidence_type: evidence.evidence_type
    )
  end

  # #868 — a rejected upload must say what was wrong and leave the form filled
  # in. Rendering (not redirecting) preserves the metadata the user typed;
  # losing it on a rejected file is its own small betrayal.
  def reject_upload(error, template)
    audit_log("evidence_upload_rejected", subject: @evidence,
              metadata: { reason: error.message, filename: uploaded_file.try(:original_filename) })
    flash.now[:error] = error.message
    @evidence ||= Evidence.new(evidence_params)
    render template, status: :unprocessable_entity
  end

  # #902 — the user chose a file and the record saved without one. Rare, but it
  # is the exact shape of the failure this issue is about, so it gets a check
  # rather than an assumption.
  def file_posted_but_not_attached?
    uploaded_file.present? && !@evidence.file.attached?
  end

  def missing_attachment_error(evidence)
    "Evidence '#{evidence.title}' was saved, but the file did NOT attach and is " \
    "not stored. Use Edit to upload it again before relying on this record."
  end

  # #868 — confirm the FILE landed, not merely that a record was created.
  # Evidence is a compliance artefact; "did my file attach, intact?" deserves a
  # direct answer, and the SHA-256 is already computed by this point.
  def upload_success_notice(evidence)
    return "Evidence '#{evidence.title}' saved." unless evidence.file.attached?

    parts = [ "Evidence '#{evidence.title}' uploaded successfully." ]
    parts << "File: #{evidence.original_filename || evidence.file.filename}"
    parts << "(#{helpers.number_to_human_size(evidence.file_size)})" if evidence.file_size.present?
    parts << "SHA-256 #{evidence.file_hash.first(16)}…" if evidence.file_hash.present?
    parts.join(" ")
  end

  def process_file_upload
    @evidence.compute_file_hash!
  end

  def sync_control_links
    control_ids = params.dig(:evidence, :control_ids).to_s.split(",").map(&:strip).reject(&:blank?)
    return if control_ids.empty? && !params.dig(:evidence, :control_ids)

    @evidence.evidence_control_links.destroy_all
    control_ids.each do |cid|
      @evidence.evidence_control_links.create!(control_id: cid)
    end
  end
end
