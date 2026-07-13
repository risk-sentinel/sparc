# Polymorphic CRUD for BackMatterResource records nested under any
# OSCAL document type. Handles create, update, and destroy of managed
# back-matter resources from the document show page.
#
# Routes expect a parent document identified by :document_type and
# :document_id (slug). The controller resolves the polymorphic parent
# and scopes all operations to it.
#
# NIST SA-10: Developer Configuration Management
class BackMatterResourcesController < ApplicationController
  before_action :set_document
  before_action :set_resource, only: %i[update destroy]
  before_action :require_draft, only: %i[create update destroy]

  def create
    @resource = @document.back_matter_resources.build(resource_params)
    @resource.uuid = SecureRandom.uuid if @resource.uuid.blank?
    @resource.source = "managed"
    @resource.organization = current_user.organizations.first if current_user.organizations.any?

    if @resource.save
      link_to_control_if_requested(@resource)
      @document.regenerate_oscal_uuid! if @document.respond_to?(:regenerate_oscal_uuid!)
      audit_log("back_matter_resource_created", subject: @resource,
                metadata: { title: @resource.title, document: @document.class.name })
      flash[:success] = "Back-matter resource \"#{@resource.title}\" added"
    else
      flash[:error] = "Could not add resource: #{@resource.errors.full_messages.join(', ')}"
    end

    redirect_to document_show_path
  end

  def update
    if @resource.update(resource_params)
      @document.regenerate_oscal_uuid! if @document.respond_to?(:regenerate_oscal_uuid!)
      audit_log("back_matter_resource_updated", subject: @resource,
                metadata: { title: @resource.title })
      flash[:success] = "Resource \"#{@resource.title}\" updated"
    else
      flash[:error] = "Could not update resource: #{@resource.errors.full_messages.join(', ')}"
    end

    redirect_to document_show_path
  end

  def destroy
    title = @resource.title
    audit_log("back_matter_resource_deleted", subject: @resource,
              metadata: { title: title })
    @resource.destroy
    @document.regenerate_oscal_uuid! if @document.respond_to?(:regenerate_oscal_uuid!)
    flash[:success] = "Resource \"#{title}\" removed"
    redirect_to document_show_path
  end

  private

  # ── Parent document resolution ──────────────────────────────────────

  # Maps Rails param key (from nested route) to model class.
  # e.g., :ssp_document_id => SspDocument
  PARENT_PARAMS = {
    "ssp_document_id"      => SspDocument,
    "sar_document_id"      => SarDocument,
    "sap_document_id"      => SapDocument,
    "cdef_document_id"     => CdefDocument,
    "poam_document_id"     => PoamDocument,
    "profile_document_id"  => ProfileDocument,
    "control_catalog_id"   => ControlCatalog
  }.freeze

  def set_document
    found = PARENT_PARAMS.find { |param_key, _klass| params[param_key].present? }
    if found
      param_key, klass = found
      @document = klass.find_by!(slug: params[param_key])
      return
    end

    raise ActiveRecord::RecordNotFound, "No parent document found"
  end

  def set_resource
    @resource = @document.back_matter_resources.find(params[:id])
  end

  def require_draft
    return unless @document.respond_to?(:draft?)
    return if @document.draft?

    flash[:error] = "Back-matter resources can only be modified on draft documents"
    redirect_to document_show_path
  end

  def resource_params
    params.require(:back_matter_resource).permit(
      :title, :description, :href, :media_type, :rel, :globally_available
    )
  end

  # If the form included a "link_to_control" param (e.g. "CdefControl:42"),
  # create a ControlBackMatterLink joining the resource to that control.
  def link_to_control_if_requested(resource)
    link_param = params[:link_to_control]
    return if link_param.blank?

    type, id = link_param.split(":", 2)
    return unless %w[CatalogControl CdefControl ProfileControl SspControl].include?(type)

    control = type.constantize.find_by(id: id)
    return unless control

    control.control_back_matter_links.create(back_matter_resource: resource)
  end

  # ── Redirect helpers ────────────────────────────────────────────────

  def document_show_path
    case @document
    when SspDocument      then ssp_document_path(@document)
    when SarDocument      then sar_document_path(@document)
    when SapDocument      then sap_document_path(@document)
    when CdefDocument     then cdef_document_path(@document)
    when PoamDocument     then poam_document_path(@document)
    when ProfileDocument  then profile_document_path(@document)
    when ControlCatalog   then control_catalog_path(@document)
    else raise ArgumentError, "Unknown document type: #{@document.class}"
    end
  end
end
