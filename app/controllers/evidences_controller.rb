class EvidencesController < ApplicationController
  before_action :set_evidence, only: [ :show, :edit, :update, :destroy ]

  def index
    @total_count = Evidence.count
    @link_count = EvidenceControlLink.count

    @evidences = Evidence.order(created_at: :desc)
    @evidences = @evidences.where(evidence_type: params[:type]) if params[:type].present?
    @evidences = @evidences.where(status: params[:status]) if params[:status].present?
    @evidences = @evidences.where(project_id: params[:project_id]) if params[:project_id].present?

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
    @evidence.collected_at ||= Time.current

    if @evidence.save
      process_file_upload if @evidence.file.attached?
      sync_control_links
      redirect_to @evidence, notice: "Evidence '#{@evidence.title}' uploaded successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @evidence.update(evidence_params)
      process_file_upload if @evidence.file.attached? && @evidence.file_hash.blank?
      sync_control_links
      redirect_to @evidence, notice: "Evidence updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @evidence.title
    @evidence.destroy
    redirect_to evidences_path, notice: "Evidence '#{title}' deleted."
  end

  private

  def set_evidence
    @evidence = Evidence.find(params[:id])
  end

  def evidence_params
    params.require(:evidence).permit(
      :title, :description, :evidence_type, :status,
      :collected_at, :collected_by, :source, :project_id, :file
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
