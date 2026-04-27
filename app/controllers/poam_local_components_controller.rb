# Admin UI for OSCAL POA&M `local-definitions.components` (#423).
#
# Components describe the systems/services this POA&M scopes against
# (databases, services, infrastructure pieces). No origins per OSCAL
# component schema — only props and links.
class PoamLocalComponentsController < ApplicationController
  include OscalExtensibilityParams

  before_action :set_poam_document
  before_action :set_poam_local_component, only: %i[edit update destroy]

  def new
    @poam_local_component = @poam_document.poam_local_components.build
  end

  def create
    @poam_local_component = @poam_document.poam_local_components.build(poam_local_component_params)
    @poam_local_component.uuid ||= SecureRandom.uuid

    if @poam_local_component.save
      audit_log("poam_local_component_created", subject: @poam_local_component,
                metadata: { title: @poam_local_component.title, poam_document_id: @poam_document.id })
      flash[:success] = "Component added"
      redirect_to poam_document_path(@poam_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @poam_local_component.update(poam_local_component_params)
      audit_log("poam_local_component_updated", subject: @poam_local_component,
                metadata: { title: @poam_local_component.title })
      flash[:success] = "Component updated"
      redirect_to poam_document_path(@poam_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_local_component.title
    audit_log("poam_local_component_deleted", subject: @poam_local_component, metadata: { title: title })
    @poam_local_component.destroy
    flash[:success] = "Component \"#{title}\" removed"
    redirect_to poam_document_path(@poam_document)
  end

  private

  def set_poam_document
    @poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])
  end

  def set_poam_local_component
    @poam_local_component = @poam_document.poam_local_components.find(params[:id])
  end

  def poam_local_component_params
    permitted = params.require(:poam_local_component).permit(
      :title, :description, :component_type, :purpose, :remarks,
      :status_state, :status_remarks,
      props_data: [ :name, :value, :class, :ns, :uuid, :remarks ],
      links_data: [ :href, :rel, :media_type, :text ]
    )
    permitted[:props_data] = compact_props(permitted[:props_data]) if permitted.key?(:props_data)
    permitted[:links_data] = compact_links(permitted[:links_data]) if permitted.key?(:links_data)
    permitted
  end
end
