class ControlFamiliesController < ApplicationController
  skip_before_action :require_authentication, only: [ :show ]

  before_action :set_control_catalog, only: [ :new, :create ]
  before_action :set_control_family, only: [ :show, :edit, :update, :destroy ]
  # #881 — numeric family URLs converge on the catalog-scoped, code-addressed one.
  before_action :redirect_legacy_family_url, only: [ :show ]
  before_action :authorize_catalog_write!, only: [ :new, :create, :edit, :update, :destroy ]

  def show
    @catalog_controls = @control_family.catalog_controls.order(:control_id)
    @control_catalog = @control_family.control_catalog
  end

  def new
    @control_family = @control_catalog.control_families.new
  end

  def create
    @control_family = @control_catalog.control_families.new(control_family_params)
    if @control_family.save
      audit_log("control_family_created", subject: @control_family, metadata: { code: @control_family.code, name: @control_family.name })
      redirect_to @control_family, notice: "Family '#{@control_family.code} - #{@control_family.name}' was created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @control_catalog = @control_family.control_catalog
  end

  def update
    if @control_family.update(control_family_params)
      audit_log("control_family_updated", subject: @control_family, metadata: { code: @control_family.code, name: @control_family.name })
      redirect_to @control_family, notice: "Family updated successfully."
    else
      @control_catalog = @control_family.control_catalog
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    catalog = @control_family.control_catalog
    code = @control_family.code
    name = @control_family.name
    audit_log("control_family_deleted", subject: @control_family, metadata: { code: code, name: name })
    @control_family.destroy
    redirect_to catalog, notice: "Family was deleted."
  end

  private

  def set_control_catalog
    @control_catalog = ControlCatalog.find_for_url(params[:control_catalog_id]) || raise(ActiveRecord::RecordNotFound)
  end

  # #881 — inside a catalog a family is addressed by its code (`ac`), which is
  # unique per catalog and is what the control ids already encode.
  def set_control_family
    @control_family =
      if params[:control_catalog_id].present?
        catalog = ControlCatalog.find_for_url(params[:control_catalog_id])
        catalog&.control_families&.find_by("LOWER(code) = ?", params[:id].to_s.downcase) ||
          raise(ActiveRecord::RecordNotFound, "No family #{params[:id].inspect} in this catalog")
      else
        ControlFamily.find(params[:id])
      end
  end

  def control_family_params
    params.require(:control_family).permit(:code, :name, :description, :sort_order)
  end

  def redirect_legacy_family_url
    return if params[:control_catalog_id].present?
    # HEAD is GET without a body, but `request.get?` is false for it — so a
    # HEAD on a legacy URL skipped the 301 and resolved in place, and caches
    # and crawlers never saw the canonical location. Writes still resolve in
    # place, which is the behaviour this guard exists for.
    return unless request.get? || request.head?

    catalog = @control_family.control_catalog
    return if catalog.nil?

    # Carry the format across — a redirect that drops `.json` hands the caller
    # an HTML page where it asked for JSON, and fetch() follows it silently.
    # Same defect as control_catalogs_controller; see the note there.
    redirect_to control_catalog_family_path(catalog.url_id, @control_family.code.downcase,
                                            format: params[:format]),
                status: :moved_permanently
  end

  def authorize_catalog_write!
    authorize_permission!("catalogs.write")
  end
end
