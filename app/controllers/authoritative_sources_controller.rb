# NC/LC discovery UI for the authoritative back-matter library (#372).
# Browse + filter, plus add (#646). "use in document" actions go through the
# existing back-matter resource controllers.
#
# #646 — any authenticated user can ADD a source. By default it is scoped to
# the user's organization/boundary (globally_available = false, organization
# set). The "instance-wide" availability flag reuses the existing promotion
# approval (BackMatterResourcePromotionService): users with promotion authority
# (instance admin / policy_manager / boundary AO roles) self-approve to
# instance-wide immediately; everyone else's request lands in the promotion
# queue for an approver. Nothing here grants instance-wide without that gate.
class AuthoritativeSourcesController < ApplicationController
  include CollectionViewable
  before_action :authorize_read!,  only: %i[index show]
  before_action :set_resource,     only: %i[edit update destroy restore link_control unlink_control]
  before_action :authorize_write!, only: %i[edit update destroy restore link_control unlink_control]

  # #888 — the facets this screen offers; the chrome that renders them is shared.
  SOURCE_FACETS = %i[scope rel media_type].freeze
  SOURCE_FACET_LABELS = { scope: "Scope", rel: "Rel", media_type: "Media type" }.freeze

  def index
    scope = visible_resources

    if params[:scope] == "global"
      scope = scope.where(globally_available: true)
    elsif params[:scope] == "authoritative"
      scope = scope.authoritative
    end

    scope = scope.where(rel: params[:rel])               if params[:rel].present?
    scope = scope.where(media_type: params[:media_type]) if params[:media_type].present?

    # #888 — search now goes through the shared scope, so this screen matches
    # href as well as title and description. BackMatterResource declares those
    # columns; nothing here needs to know which.
    scope = scope.search_text(params[:q])

    @total = scope.count

    # The old `.limit(200)` silently dropped everything past the 200th row with
    # nothing on the page to say so — a library you cannot reach the end of.
    # Pagination replaces it.
    @view_mode = resolve_view_mode(:authoritative_sources)
    @facets = active_facets(SOURCE_FACETS, labels: SOURCE_FACET_LABELS)
    @clear_facets = clear_facets_params(SOURCE_FACETS)
    @pagy, @resources = paginate_collection(scope.order(updated_at: :desc))
  end

  def show
    # NOT `visible_resources`: that scope is `.active`, so an archived source
    # would 404 on the very screen that offers Restore — archive would be a
    # one-way door. Scope is still enforced, just without the active filter.
    @resource = BackMatterResource.find(params[:id])
    return if current_user.admin?
    return if @resource.globally_available? ||
              current_user.organizations.ids.include?(@resource.organization_id)

    flash[:error] = "Not authorized for that source"
    redirect_to authoritative_sources_path
  end

  def new
    @resource = BackMatterResource.new(rel: "reference")
  end

  def create
    result = AuthoritativeSourceCreator.call(
      actor: current_user,
      attrs: resource_params,
      instance_wide: params[:instance_wide]
    )

    if result.success?
      audit_log("authoritative_source_created", subject: result.resource,
                metadata: { title: result.resource.title, availability: result.message })
      flash[:success] = "Source added — #{result.message}."
      redirect_to authoritative_sources_path
    else
      @resource = result.resource
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @resource.update(resource_params)
      audit_log("authoritative_source_updated", subject: @resource,
                metadata: { title: @resource.title })
      flash[:success] = "Source updated."
      redirect_to authoritative_source_path(@resource)
    else
      render :edit, status: :unprocessable_content
    end
  end

  # ARCHIVE, not delete. These resources participate in federation
  # (federated_from_instance / original_uuid) and promotion, so a hard delete
  # strands a federated copy on a peer with nothing to reconcile against. A
  # reference already cited by a document also stays citable — archiving takes
  # it out of the picker, not out of history. Owner-decided 2026-08-23.
  def destroy
    @resource.update!(archived_at: Time.current)
    audit_log("authoritative_source_archived", subject: @resource,
              metadata: { title: @resource.title })
    flash[:success] = "Source archived. It stays citable where already used, and can be restored."
    redirect_to authoritative_sources_path
  end

  def restore
    @resource.update!(archived_at: nil)
    audit_log("authoritative_source_restored", subject: @resource,
              metadata: { title: @resource.title })
    flash[:success] = "Source restored."
    redirect_to authoritative_source_path(@resource)
  end

  # Control references, through a nested action rather than inline on create --
  # `evidences` already attaches controls this way with `control_links`, and a
  # second mechanism for "attach a control to a thing" is exactly the divergence
  # #1039's scope note warned about.
  # A reference is only useful to an assessor if it resolves. The first cut took
  # a raw `linkable_id` and called `find`, which meant a typo produced a 404 and
  # nothing recorded WHICH catalog a control id belonged to — with Rev 4 and
  # Rev 5 loaded simultaneously, a bare "AC-2" names a control in each of them.
  #
  # Catalog controls are therefore resolved by (catalog, control id), the pair
  # that is actually unique, and the id is matched through `ControlId` so the
  # caller can type AC-2, ac-02, or AC-02 and mean the same control.
  def link_control
    type = params[:linkable_type].to_s
    unless BackMatterResource::LINKABLE_CONTROL_TYPES.include?(type)
      flash[:error] = "Unsupported control type."
      return redirect_back_to_source
    end

    control = if type == "CatalogControl"
                resolve_catalog_control
    else
                type.constantize.find_by(id: params[:linkable_id])
    end

    unless control
      flash[:error] = catalog_control_not_found_message(type)
      return redirect_back_to_source
    end

    link = @resource.control_back_matter_links.build(linkable: control)
    if link.save
      audit_log("authoritative_source_control_linked", subject: @resource,
                metadata: { control_type: type, control_id: control.id })
      flash[:success] = "Control reference added."
    else
      flash[:error] = link.errors.full_messages.to_sentence.presence || "Could not add that control reference."
    end
    redirect_back_to_source
  end

  def unlink_control
    link = @resource.control_back_matter_links.find(params[:link_id])
    link.destroy!
    audit_log("authoritative_source_control_unlinked", subject: @resource,
              metadata: { link_id: params[:link_id] })
    flash[:success] = "Control reference removed."
    redirect_back_to_source
  end

  private

  # Scoped to the chosen catalog, so the same control id in Rev 4 and Rev 5
  # stays two distinct references rather than whichever row happened to be first.
  def resolve_catalog_control
    catalog = ControlCatalog.find_by(id: params[:control_catalog_id])
    return nil unless catalog

    wanted = ControlId.canonical(params[:control_identifier])
    return nil if wanted.blank?

    CatalogControl
      .joins(control_family: :control_catalog)
      .where(control_families: { control_catalog_id: catalog.id })
      .find { |c| ControlId.same?(c.control_id, wanted) }
  end

  def catalog_control_not_found_message(type)
    if type == "CatalogControl"
      "No control matching #{params[:control_identifier].to_s.strip.presence || "that id"} " \
        "in the selected catalog."
    else
      "That control could not be found."
    end
  end

  # Linking is offered from both `show` and `edit`; return the caller to the one
  # they were on rather than always bouncing to `show`.
  def redirect_back_to_source
    if params[:return_to] == "edit"
      redirect_to edit_authoritative_source_path(@resource)
    else
      redirect_to authoritative_source_path(@resource)
    end
  end


  def set_resource
    # Deliberately NOT `visible_resources`: that scope is `.active`, so an
    # archived source would 404 on the very screen that restores it.
    @resource = BackMatterResource.find(params[:id])
    return if current_user.admin?
    return if @resource.globally_available? ||
              current_user.organizations.ids.include?(@resource.organization_id)

    flash[:error] = "Not authorized for that source"
    redirect_to authoritative_sources_path
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.write")

    flash[:error] = "Not authorized to change authoritative sources"
    redirect_to authoritative_sources_path
  end

  # Resources the current user may see: globally-available + their org's, or
  # everything for an instance admin.
  def visible_resources
    base = BackMatterResource.active
    return base if current_user.admin?

    org_ids = current_user.organizations.ids
    if org_ids.any?
      base.where("globally_available = ? OR organization_id IN (?)", true, org_ids)
    else
      base.where(globally_available: true)
    end
  end

  def resource_params
    params.require(:back_matter_resource)
          .permit(:title, :description, :href, :rel, :media_type,
                  :organization_id, :provided_by_team, :provided_by_contact)
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.read")

    flash[:error] = "Not authorized to view authoritative sources"
    redirect_to root_path
  end
end
