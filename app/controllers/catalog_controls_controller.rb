class CatalogControlsController < ApplicationController
  # #881 — `show` is a READ of catalog content, so it follows the same posture
  # as control_catalogs#show and control_families#show: reachable without
  # authentication only when the deployment opts into public controls (#726),
  # and never gated on catalogs.write. The write gate below was previously
  # unscoped, which was harmless while every action was a write.
  # #726/#974 — public read when SPARC_PUBLIC_CATALOGS=true, authenticated otherwise.
  public_controls_read only: [ :show ]

  before_action :set_control_family, only: [ :new, :create, :batch_new, :batch_create ]
  before_action :set_catalog_control, only: [ :show, :edit, :update, :destroy ]
  # #881 — legacy numeric URLs converge on the readable one.
  before_action :redirect_legacy_identifier, only: [ :show, :edit ]
  before_action :authorize_catalog_write!, except: [ :show ]

  # #881 — a control's own page. Controls were previously only visible inside
  # the family aggregate, so there was nothing to link to or cite; sub-parts
  # (48% of rows) had no address at all.
  def show
    @control_family  = @catalog_control.control_family
    @control_catalog = @control_family.control_catalog
    # Direct children only. A prefix match would be wrong: `ac-10` starts with
    # `ac-1` but is a separate control, not a sub-part of it.
    @sub_parts = @catalog_control.direct_children
    @linked_resources = @catalog_control.back_matter_resources.order(:title)
  end

  def new
    @catalog_control = @control_family.catalog_controls.new
  end

  def create
    permitted = catalog_control_params
    @catalog_control = @control_family.catalog_controls.new(permitted.except(:params_labels))
    apply_params_labels!(permitted)
    if @catalog_control.save
      audit_log("catalog_control_created", subject: @catalog_control, metadata: { control_id: @catalog_control.control_id })
      redirect_to @control_family, notice: "Control '#{@catalog_control.control_id}' was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @control_family = @catalog_control.control_family
    load_available_resources
  end

  def update
    permitted = catalog_control_params
    apply_params_labels!(permitted)
    if @catalog_control.update(permitted.except(:params_labels))
      audit_log("catalog_control_updated", subject: @catalog_control, metadata: { control_id: @catalog_control.control_id })
      redirect_to @catalog_control.control_family, notice: "Control updated successfully."
    else
      @control_family = @catalog_control.control_family
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    family = @catalog_control.control_family
    audit_log("catalog_control_deleted", subject: @catalog_control, metadata: { control_id: @catalog_control.control_id })
    @catalog_control.destroy
    redirect_to family, notice: "Control was deleted."
  end

  def batch_new
    @control_catalog = @control_family.control_catalog
  end

  def batch_create
    controls_text = params[:controls_text].to_s.strip
    if controls_text.blank?
      @control_catalog = @control_family.control_catalog
      flash.now[:error] = "Please enter at least one control."
      return render :batch_new, status: :unprocessable_entity
    end

    created = 0
    errors = []

    ActiveRecord::Base.transaction do
      controls_text.each_line do |line|
        line = line.strip
        next if line.blank?

        control_id, title = line.split(/[|,]/, 2).map(&:strip)
        control_id = control_id.to_s.strip
        title = title.to_s.strip.presence

        next if control_id.blank?

        control = @control_family.catalog_controls.build(control_id: control_id, title: title)
        if control.save
          created += 1
        else
          errors << "#{control_id}: #{control.errors.full_messages.join(', ')}"
        end
      end
    end

    if errors.any?
      @control_catalog = @control_family.control_catalog
      flash.now[:error] = "#{created} controls added. Errors: #{errors.join('; ')}"
      render :batch_new, status: :unprocessable_entity
    else
      audit_log("catalog_control_created", subject: @control_family, metadata: { count: created, family_id: @control_family.id })
      redirect_to @control_family, notice: "#{created} #{'control'.pluralize(created)} added successfully."
    end
  end

  private

  def set_control_family
    @control_family = ControlFamily.find(params[:control_family_id])
  end

  # #881 — resolve a control by its canonical identifier when the route is
  # catalog-scoped (`/control_catalogs/<slug>/controls/ac-19.4.b.1`), and by
  # database id on the legacy shallow route.
  #
  # The legacy route stays resolvable so existing bookmarks and any link already
  # in the wild keep working, but `redirect_legacy_identifier` sends them on with
  # a 301 so they converge on the readable URL rather than both forms living
  # forever.
  def set_catalog_control
    @catalog_control =
      if params[:control_catalog_id].present?
        CatalogControl.find_by_canonical(current_control_catalog, params[:id]) ||
          raise(ActiveRecord::RecordNotFound, "No control #{params[:id].inspect} in this catalog")
      else
        CatalogControl.find(params[:id])
      end
  end

  def current_control_catalog
    @current_control_catalog ||= ControlCatalog.find_for_url(params[:control_catalog_id])
  end

  # 301 the legacy numeric URL to the canonical one. GET only: a redirect
  # preserves the method for 301, but re-issuing a PATCH/DELETE through a
  # redirect is not something to rely on, so writes simply resolve in place.
  def redirect_legacy_identifier
    return if params[:control_catalog_id].present?
    # HEAD is GET without a body, but `request.get?` is false for it — so a
    # HEAD on a legacy URL skipped the 301 and resolved in place, and caches
    # and crawlers never saw the canonical location. Writes still resolve in
    # place, which is the behaviour this guard exists for.
    return unless request.get? || request.head?

    catalog = @catalog_control.control_family&.control_catalog
    return if catalog.nil?

    target = action_name == "edit" ? :edit : :show
    # Carry the format across — a redirect that drops `.json` hands the caller
    # an HTML page where it asked for JSON, and fetch() follows it silently.
    # Same defect as control_catalogs_controller; see the note there.
    fmt = params[:format]
    path = if target == :edit
      control_catalog_edit_control_path(catalog.url_id, @catalog_control.canonical_identifier, format: fmt)
    else
      control_catalog_control_path(catalog.url_id, @catalog_control.canonical_identifier, format: fmt)
    end
    redirect_to path, status: :moved_permanently
  end

  def catalog_control_params
    permitted = params.require(:catalog_control).permit(
      :control_id, :title, :description, :priority, :baseline_impact,
      guidance_data: {},
      params_labels: {},
      baseline_levels: []
    )

    # Convert checkbox array to comma-separated string
    if params[:catalog_control].key?(:baseline_levels)
      levels = Array(permitted.delete(:baseline_levels)).select(&:present?).map(&:upcase)
      permitted[:baseline_impact] = levels.any? ? levels.join(", ") : nil
    end

    permitted
  end

  # Extracts params_labels from the permitted params hash and merges
  # the updated labels back into @catalog_control.params_data.
  def apply_params_labels!(permitted)
    labels = permitted[:params_labels]
    return if labels.blank?

    @catalog_control.params_data = @catalog_control.merge_params_labels(labels.to_h)
  end

  def load_available_resources
    @linked_resources = @catalog_control.back_matter_resources.order(:title)
    org = current_user.organizations.first
    @available_resources = if org
      BackMatterResource.org_available(org.id)
                         .where.not(id: @linked_resources.select(:id))
                         .order(:title)
    else
      BackMatterResource.globally_available
                         .where.not(id: @linked_resources.select(:id))
                         .order(:title)
    end
  end

  def authorize_catalog_write!
    authorize_permission!("catalogs.write")
  end
end
