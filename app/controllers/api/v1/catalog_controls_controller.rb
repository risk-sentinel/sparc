# REST API for the controls inside a catalog (#895).
#
# Second slice of the Catalog API, after control_families. The web UI has been
# able to add, tailor and delete catalog controls all along; the API could not
# reach them at all. This is the API catching up to a shipping UI.
#
# Addressing follows #881: a control is identified by its CANONICAL IDENTIFIER
# (`ac-2`, `ac-19.4.b.1`) — the same form every OSCAL exporter writes as
# `control-id`, and the same form the readable web URLs use. `(catalog,
# canonical_id)` is unique across all seeded catalogs, so the family does not
# need to appear in the path for reads or updates. Creation IS family-scoped,
# because a control has to be put somewhere.
#
# GET    /api/v1/control_catalogs/:catalog/controls                      — list a catalog's controls
# GET    /api/v1/control_catalogs/:catalog/controls/:id                  — show
# PATCH  /api/v1/control_catalogs/:catalog/controls/:id                  — update (tailoring)
# DELETE /api/v1/control_catalogs/:catalog/controls/:id                  — delete
# GET    /api/v1/control_catalogs/:catalog/control_families/:code/controls — list a family's controls
# POST   /api/v1/control_catalogs/:catalog/control_families/:code/controls — create
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (catalog write permission gates every mutation)
#   AU-2 Audit Events (every mutation is audited)
#   CM-3 Configuration Change Control (catalog tailoring is attributable)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::CatalogControlsController < Api::V1::BaseController
  before_action :set_control_catalog
  before_action :set_control_family, if: -> { params[:control_family_id].present? }
  before_action :authorize_catalog_write!, only: [ :create, :update, :destroy ]
  before_action :set_catalog_control, only: [ :show, :update, :destroy ]

  # GET …/controls  or  …/control_families/:code/controls
  def index
    scope = base_scope.includes(:control_family)
    scope = scope.where(control_families: { id: @control_family.id }) if @control_family
    scope = apply_filters(scope)

    result = paginate(scope)
    render json: {
      data: result[:data].map { |c| serialize_control(c) },
      meta: result[:meta]
    }
  end

  # GET …/controls/:id
  def show
    render json: { data: serialize_control(@catalog_control, detailed: true) }
  end

  # POST …/control_families/:code/controls
  def create
    return if render_invalid_baseline

    control = @control_family.catalog_controls.new(create_attributes)
    control.save!

    audit_log("api_catalog_control_created", subject: control,
              metadata: audit_metadata(control))
    render json: { data: serialize_control(control, detailed: true) }, status: :created
  end

  # PATCH …/controls/:id
  def update
    return if render_invalid_baseline

    @catalog_control.assign_attributes(update_attributes)
    @catalog_control.save!

    audit_log("api_catalog_control_updated", subject: @catalog_control,
              metadata: audit_metadata(@catalog_control).merge(fields: changed_field_names))
    render json: { data: serialize_control(@catalog_control, detailed: true) }
  end

  # DELETE …/controls/:id
  def destroy
    identifier = @catalog_control.canonical_identifier
    children = @catalog_control.direct_children

    # Refuse rather than orphan. Sub-parts are separate rows (48% of the seeded
    # catalogs) with no foreign key to their parent, so deleting `ac-1` would
    # leave `ac-1a` behind pointing at a control that no longer exists.
    if children.any?
      return render json: {
        error: "Control #{identifier} still has #{children.size} sub-part(s). Delete them first.",
        sub_parts: children.map(&:canonical_identifier)
      }, status: :unprocessable_entity
    end

    @catalog_control.destroy!
    audit_log("api_catalog_control_deleted", subject: @catalog_control,
              metadata: audit_metadata(@catalog_control))
    render json: { data: { identifier: identifier, deleted: true } }
  end

  private

  # #881/#895 — uuid, slug or numeric id. The uuid is the stable identity.
  def set_control_catalog
    @control_catalog = ControlCatalog.find_for_url(params[:control_catalog_id]) ||
                       raise(ActiveRecord::RecordNotFound, "No catalog #{params[:control_catalog_id].inspect}")
  end

  def set_control_family
    @control_family = @control_catalog.control_families
                                      .find_by("LOWER(code) = ?", params[:control_family_id].to_s.downcase) ||
                      raise(ActiveRecord::RecordNotFound,
                            "No family #{params[:control_family_id].inspect} in this catalog")
  end

  # Catalog-scoped, never bare id: a database id from another catalog must not
  # resolve here just because the caller happened to know it.
  def set_catalog_control
    @catalog_control = CatalogControl.find_by_canonical(@control_catalog, params[:id]) ||
                       raise(ActiveRecord::RecordNotFound,
                             "No control #{params[:id].inspect} in this catalog")
  end

  def base_scope
    CatalogControl.joins(control_family: :control_catalog)
                  .where(control_families: { control_catalog_id: @control_catalog.id })
  end

  def apply_filters(scope)
    scope = scope.where(control_families: { code: params[:family].to_s.upcase }) if params[:family].present?
    scope = scope.top_level if ActiveModel::Type::Boolean.new.cast(params[:top_level])
    scope = scope.where("baseline_impact ILIKE ?", "%#{params[:baseline]}%") if params[:baseline].present?
    if params[:q].present?
      term = "%#{params[:q]}%"
      scope = scope.where("catalog_controls.control_id ILIKE :q OR catalog_controls.title ILIKE :q", q: term)
    end
    scope
  end

  def authorize_catalog_write!
    return if current_user.admin?
    return if current_user.has_permission?("catalogs.write")

    raise NotAuthorizedError, "Not authorized to modify catalog content"
  end

  # ── Parameters ────────────────────────────────────────────────────────────
  #
  # Enumerated deliberately, and enumerated all the way down. The web form
  # permits `guidance_data: {}` — an arbitrary hash — which is safe for a form
  # posting known inputs and unsafe for a public endpoint, because that column
  # is read by every OSCAL exporter. The key lists live on the model
  # (CatalogControl.guidance_params_filter / .params_data_filter) so the schema
  # is stated in one place.
  def control_params
    params.require(:catalog_control).permit(
      :control_id, :title, :description, :priority, :label, :sort_id, :baseline_impact,
      baseline_levels: [],
      guidance_data: CatalogControl.guidance_params_filter,
      params_labels: {},
      params_data: CatalogControl.params_data_filter
    )
  end

  def create_attributes
    permitted = control_params
    attrs = scalar_attributes(permitted)
    attrs[:guidance_data] = CatalogControl.normalize_guidance(permitted[:guidance_data].to_h) if permitted.key?(:guidance_data)
    attrs[:params_data] = permitted[:params_data].map(&:to_h) if permitted.key?(:params_data)
    attrs
  end

  def update_attributes
    permitted = control_params
    attrs = scalar_attributes(permitted)

    # Merge, don't replace — see CatalogControl#merge_guidance_data. Replacing
    # would let a one-field PATCH silently delete the rest of the guidance.
    attrs[:guidance_data] = @catalog_control.merge_guidance_data(permitted[:guidance_data].to_h) if permitted.key?(:guidance_data)

    # params_data is an ordered array, so a PATCH replaces it wholesale. Callers
    # that only want to relabel an ODP send params_labels instead.
    attrs[:params_data] = permitted[:params_data].map(&:to_h) if permitted.key?(:params_data)
    if permitted[:params_labels].present?
      attrs[:params_data] = @catalog_control.merge_params_labels(permitted[:params_labels].to_h)
    end

    attrs
  end

  def scalar_attributes(permitted)
    attrs = permitted.slice(:control_id, :title, :description, :priority, :label, :sort_id, :baseline_impact).to_h

    # Accept the levels as an array (the natural JSON shape) as well as the
    # comma-joined string the column actually stores.
    if permitted.key?(:baseline_levels)
      levels = Array(permitted[:baseline_levels]).map { |l| l.to_s.strip.upcase }.reject(&:blank?)
      attrs["baseline_impact"] = levels.any? ? levels.join(", ") : nil
    end

    attrs
  end

  # Validated here rather than on the model: the importer writes this column
  # from source catalogs in more than one notation, and a model validation
  # would start rejecting imports that work today.
  def render_invalid_baseline
    raw = params.dig(:catalog_control, :baseline_levels) || params.dig(:catalog_control, :baseline_impact)
    return false if raw.blank?

    # Split on a bare comma, NOT /\s*,\s*/. `raw` is unbounded request data, and
    # a regex with `\s*` on both sides of the delimiter backtracks polynomially
    # on a long run of spaces containing no comma (CodeQL rb/polynomial-redos).
    # The per-token `strip` below already handles the surrounding whitespace, so
    # the regex bought nothing.
    levels = raw.is_a?(Array) ? raw : raw.to_s.split(",")
    invalid = levels.map { |l| l.to_s.strip.upcase }.reject(&:blank?) - CatalogControl::BASELINE_LEVELS
    return false if invalid.empty?

    render json: {
      error: "Unknown baseline level(s): #{invalid.join(', ')}. " \
             "Expected one or more of #{CatalogControl::BASELINE_LEVELS.join(', ')}."
    }, status: :unprocessable_entity
    true
  end

  def changed_field_names
    @catalog_control.saved_changes.keys - %w[updated_at]
  end

  def audit_metadata(control)
    {
      control_catalog_id: @control_catalog.id,
      control_family_id: control.control_family_id,
      control_id: control.control_id,
      identifier: control.canonical_identifier
    }
  end

  # ── Serialization ─────────────────────────────────────────────────────────

  def serialize_control(control, detailed: false)
    data = {
      id: control.id,
      uuid: control.uuid,
      # The value to put in a URL, and what #881 made the control's identity.
      identifier: control.canonical_identifier,
      control_id: control.control_id,
      label: control.label,
      display_id: control.display_id,
      title: control.title,
      description: control.description,
      priority: control.priority,
      sort_id: control.sort_id,
      baseline_impact: control.baseline_impact,
      baseline_levels: control.baseline_levels,
      control_family_id: control.control_family_id,
      family_code: control.control_family.code,
      depth: control.depth,
      created_at: control.created_at.iso8601,
      updated_at: control.updated_at.iso8601
    }

    if detailed
      data[:guidance_data] = control.guidance_hash
      data[:params_data] = control.params_list
      data[:sub_parts] = control.direct_children.map do |child|
        { identifier: child.canonical_identifier, control_id: child.control_id, title: child.title }
      end
      data[:control_catalog] = {
        id: @control_catalog.id,
        uuid: @control_catalog.oscal_uuid,
        name: @control_catalog.name
      }
    end

    data
  end
end
