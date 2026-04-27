# Admin UI for OSCAL POA&M observations (#423).
#
# Observations are findings detected during assessment activities — the
# raw "what was seen" before it's escalated to a Risk or formal Finding.
# Items, risks, and findings reference observations through join models
# already present.
class PoamObservationsController < ApplicationController
  include OscalExtensibilityParams

  before_action :set_poam_document
  before_action :set_poam_observation, only: %i[edit update destroy]

  def new
    @poam_observation = @poam_document.poam_observations.build
  end

  def create
    @poam_observation = @poam_document.poam_observations.build(poam_observation_params)
    @poam_observation.uuid ||= SecureRandom.uuid

    if @poam_observation.save
      audit_log("poam_observation_created", subject: @poam_observation,
                metadata: { title: @poam_observation.title, poam_document_id: @poam_document.id })
      flash[:success] = "Observation added"
      redirect_to poam_document_path(@poam_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @poam_observation.update(poam_observation_params)
      audit_log("poam_observation_updated", subject: @poam_observation,
                metadata: { title: @poam_observation.title })
      flash[:success] = "Observation updated"
      redirect_to poam_document_path(@poam_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_observation.title
    audit_log("poam_observation_deleted", subject: @poam_observation, metadata: { title: title })
    @poam_observation.destroy
    flash[:success] = "Observation \"#{title}\" removed"
    redirect_to poam_document_path(@poam_document)
  end

  private

  def set_poam_document
    @poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])
  end

  def set_poam_observation
    @poam_observation = @poam_document.poam_observations.find(params[:id])
  end

  def poam_observation_params
    permitted = params.require(:poam_observation).permit(
      :title, :description, :remarks, :collected, :expires,
      props_data:   [ :name, :value, :class, :ns, :uuid, :remarks ],
      links_data:   [ :href, :rel, :media_type, :text ],
      origins_data: [ :actor_type, :actor_uuid, :role_id ]
    )
    permitted[:props_data]   = compact_props(permitted[:props_data])     if permitted.key?(:props_data)
    permitted[:links_data]   = compact_links(permitted[:links_data])     if permitted.key?(:links_data)
    permitted[:origins_data] = compact_origins(permitted[:origins_data]) if permitted.key?(:origins_data)
    permitted
  end
end
