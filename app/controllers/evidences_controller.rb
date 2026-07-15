class EvidencesController < ApplicationController
  include BoundaryScopedDocument
  boundary_scoped Evidence, read: "evidence.read", write: "evidence.write"

  before_action :set_evidence, only: [ :show, :edit, :update, :destroy ]
  # #738: boundary-scoped access. show = read; edit/update/destroy/create = write.
  before_action :authorize_document_read!, only: [ :show ]
  before_action :authorize_document_write!, only: [ :edit, :update, :destroy, :create ]

  def index
    @evidences = boundary_scoped_relation(Evidence).order(created_at: :desc)
    @total_count = @evidences.count
    @link_count = EvidenceControlLink.where(evidence_id: boundary_scoped_relation(Evidence).select(:id)).count

    @evidences = @evidences.where(evidence_type: params[:type]) if params[:type].present?
    @evidences = @evidences.where(status: params[:status]) if params[:status].present?
    @evidences = @evidences.where(authorization_boundary_id: params[:authorization_boundary_id]) if params[:authorization_boundary_id].present?

    if params[:control_id].present?
      evidence_ids = EvidenceControlLink.where(control_id: params[:control_id]).select(:evidence_id)
      @evidences = @evidences.where(id: evidence_ids)
    end

    if params[:search].present?
      term = "%#{params[:search]}%"
      @evidences = @evidences.where("title ILIKE :q OR description ILIKE :q OR original_filename ILIKE :q", q: term)
    end
  end

  def show
    @attestations = @evidence.attestations.order(attested_at: :desc)
    @control_links = @evidence.evidence_control_links.order(:control_id)
  end

  def new
    @evidence = Evidence.new
  end

  def create
    @evidence = Evidence.new(evidence_params)
    # #738: collection provenance is system-recorded (UTC, no DST drift), not self-asserted.
    @evidence.collected_at = Time.current.utc
    @evidence.collected_by = current_user&.display_name.presence || current_user&.email

    if @evidence.save
      audit_log("evidence_created", subject: @evidence, metadata: { title: @evidence.title })
      process_file_upload if @evidence.file.attached?
      sync_control_links
      redirect_to @evidence, notice: "Evidence '#{@evidence.title}' uploaded successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  def update
    if @evidence.update(evidence_params)
      audit_log("evidence_updated", subject: @evidence, metadata: { title: @evidence.title })
      process_file_upload if @evidence.file.attached? && @evidence.file_hash.blank?
      sync_control_links
      redirect_to @evidence, notice: "Evidence updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @evidence.title
    audit_log("evidence_deleted", subject: @evidence, metadata: { title: title })
    @evidence.destroy
    redirect_to evidences_path, notice: "Evidence '#{title}' deleted."
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
