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
  before_action :authorize_read!, only: %i[index show]

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
    @resource = visible_resources.find(params[:id])
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

  private

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
          .permit(:title, :description, :href, :rel, :media_type)
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.read")

    flash[:error] = "Not authorized to view authoritative sources"
    redirect_to root_path
  end
end
