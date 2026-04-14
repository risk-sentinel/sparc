# Polymorphic controller for linking back-matter resources to controls.
#
# Supports CatalogControl, CdefControl, ProfileControl, and SspControl.
# Handles three actions: create (new resource + link), link (existing resource),
# and destroy (unlink without deleting the resource).
#
# NIST SA-10: Developer Configuration Management
class ControlBackMatterLinksController < ApplicationController
  before_action :set_control
  before_action :set_link, only: :destroy

  # POST /:parent/:parent_id/control_back_matter_links
  # Creates a NEW BackMatterResource and links it to the control.
  def create
    resource = BackMatterResource.new(resource_params)
    resource.uuid = SecureRandom.uuid
    resource.source = "managed"
    resource.resourceable = resolve_document
    resource.organization = resolve_organization
    resource.globally_available = params.dig(:back_matter_resource, :globally_available) == "1"

    if resource.save
      @control.control_back_matter_links.create!(back_matter_resource: resource)
      audit_log("control_resource_created", subject: resource,
                metadata: { control: @control.control_id, title: resource.title })
      flash[:success] = "Resource \"#{resource.title}\" created and linked"
    else
      flash[:error] = "Could not create resource: #{resource.errors.full_messages.join(', ')}"
    end

    redirect_back_to_control
  end

  # POST /:parent/:parent_id/control_back_matter_links/link
  # Links an EXISTING BackMatterResource to the control.
  def link
    resource = BackMatterResource.find(params[:back_matter_resource_id])
    link = @control.control_back_matter_links.build(back_matter_resource: resource)

    if link.save
      audit_log("control_resource_linked", subject: resource,
                metadata: { control: @control.control_id, resource_uuid: resource.uuid })
      flash[:success] = "Resource \"#{resource.title}\" linked"
    else
      flash[:error] = "Could not link resource: #{link.errors.full_messages.join(', ')}"
    end

    redirect_back_to_control
  end

  # DELETE /:parent/:parent_id/control_back_matter_links/:id
  # Removes the link only — does NOT delete the resource.
  def destroy
    resource_title = @link.back_matter_resource.title
    audit_log("control_resource_unlinked", subject: @link.back_matter_resource,
              metadata: { control: @control.control_id })
    @link.destroy
    flash[:success] = "Resource \"#{resource_title}\" unlinked"

    redirect_back_to_control
  end

  private

  # ── Parent control resolution ───────────────────────────────────────

  CONTROL_PARAMS = {
    "catalog_control_id"  => CatalogControl,
    "cdef_control_id"     => CdefControl,
    "profile_control_id"  => ProfileControl,
    "ssp_control_id"      => SspControl
  }.freeze

  def set_control
    CONTROL_PARAMS.each do |param_key, klass|
      if params[param_key].present?
        @control = klass.find(params[param_key])
        @control_type = param_key.chomp("_id")
        return
      end
    end

    raise ActiveRecord::RecordNotFound, "No parent control found"
  end

  def set_link
    @link = @control.control_back_matter_links.find(params[:id])
  end

  def resource_params
    params.require(:back_matter_resource).permit(
      :title, :description, :href, :media_type, :rel
    )
  end

  # ── Context resolution ──────────────────────────────────────────────

  def resolve_document
    case @control
    when CatalogControl  then @control.control_family.control_catalog
    when CdefControl     then @control.cdef_document
    when ProfileControl  then @control.profile_document
    when SspControl      then @control.ssp_document
    end
  end

  def resolve_organization
    return current_user.organizations.first if current_user.organizations.any?
    nil
  end

  # ── Redirect helpers ────────────────────────────────────────────────

  def redirect_back_to_control
    case @control
    when CatalogControl
      redirect_to edit_catalog_control_path(@control)
    when CdefControl
      redirect_to cdef_document_path(@control.cdef_document)
    when ProfileControl
      redirect_to edit_profile_document_profile_control_path(@control.profile_document, @control)
    when SspControl
      redirect_to ssp_document_path(@control.ssp_document)
    end
  end
end
