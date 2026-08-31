# frozen_string_literal: true

class ControlMappingsController < ApplicationController
  include CollectionViewable
  # #726: index/show join the Controls layer public-read gate
  # (SPARC_PUBLIC_CATALOGS, secure-by-default). (AC-3)
  # #726/#974 — public read when SPARC_PUBLIC_CATALOGS=true, authenticated otherwise.
  # #974 — downloads follow the screens (see ControlCatalogsController).
  public_controls_read only: [ :index, :show, :download_oscal ]
  before_action :authorize_mapping_write!, only: [
    :new, :create, :edit, :update, :destroy, :publish, :deprecate
  ]
  before_action :set_control_mapping, only: [
    :show, :edit, :update, :destroy, :publish, :deprecate, :download_oscal
  ]

  def index
    scope = ControlMapping.sorted.includes(:source_catalog, :target_catalog)
    @total_count    = scope.count
    @complete_count = scope.where(status: "complete").count
    @draft_count    = scope.where(status: "draft").count

    # #888 — this screen had no search at all; a corpus you can only scroll is
    # not a corpus you can use.
    scope = scope.search_text(params[:q])

    @view_mode = resolve_view_mode(:control_mappings)
    @pagy, @control_mappings = paginate_collection(scope)
  end

  def show
    @entries = @control_mapping.control_mapping_entries.includes(:control_mapping)
    @entry   = ControlMappingEntry.new

    # #945 — the choices come from the mapping's OWN catalogs. Both are already
    # chosen and SPARC holds every control in them, so asking someone to
    # remember and retype an identifier was inventing a way to get it wrong.
    @source_control_options = catalog_control_options(@control_mapping.source_catalog)
    @target_control_options = catalog_control_options(@control_mapping.target_catalog)

    # Entries stored before the identifiers were validated. Surfaced, never
    # rewritten — a mapping records a judgement, and guessing at what someone
    # meant would destroy the thing being recorded.
    @unresolved_entries = @entries.reject(&:resolved?)
  end

  def new
    @control_mapping = ControlMapping.new
    load_catalogs
  end

  def create
    @control_mapping = ControlMapping.new(control_mapping_params)

    if @control_mapping.save
      audit_log("control_mapping_created", subject: @control_mapping, metadata: { name: @control_mapping.name })
      redirect_to @control_mapping, flash: { success: "Control mapping created." }
    else
      load_catalogs
      flash.now[:error] = "Failed to create control mapping."
      render :new, status: :unprocessable_content
    end
  end

  def edit
    load_catalogs
  end

  def update
    if @control_mapping.update(control_mapping_params)
      audit_log("control_mapping_updated", subject: @control_mapping, metadata: { name: @control_mapping.name })
      redirect_to @control_mapping, flash: { success: "Control mapping updated." }
    else
      load_catalogs
      flash.now[:error] = "Failed to update control mapping."
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    name = @control_mapping.name
    audit_log("control_mapping_deleted", subject: @control_mapping, metadata: { name: name })
    @control_mapping.destroy
    redirect_to control_mappings_path, flash: { success: "Control mapping '#{name}' deleted." }
  end

  # PATCH /control_mappings/:id/publish
  def publish
    @control_mapping.update!(status: "complete")
    audit_log("control_mapping_published", subject: @control_mapping, metadata: { name: @control_mapping.name })
    redirect_to @control_mapping, flash: { success: "Control mapping published." }
  end

  # PATCH /control_mappings/:id/deprecate
  def deprecate
    @control_mapping.update!(status: "deprecated")
    audit_log("control_mapping_deprecated", subject: @control_mapping, metadata: { name: @control_mapping.name })
    redirect_to @control_mapping, flash: { success: "Control mapping deprecated." }
  end

  # GET /control_mappings/:id/download_oscal
  def download_oscal
    service = OscalMappingExportService.new(@control_mapping)
    json_data = service.export_unvalidated

    audit_log("control_mapping_exported", subject: @control_mapping, metadata: { name: @control_mapping.name, format: "oscal" })
    send_data json_data,
              filename: "#{@control_mapping.name.parameterize}_mapping_#{Date.today}.json",
              type: "application/json",
              disposition: "attachment"
  end

  private

  # Every control in a catalog, as [label, value] for a picker (#945).
  #
  # Includes statement sub-parts, because a mapping's subject type may be
  # `statement` and #941 stores those as CatalogControl rows — so the picker
  # reaches statements without a second lookup path.
  #
  # Returns [] for a mapping with no catalog on that side, which the view reads
  # as "fall back to a free-text field": a mapping created before both catalogs
  # were required must stay editable.
  def catalog_control_options(catalog)
    return [] if catalog.nil?

    CatalogControl.unscoped
                  .joins(control_family: :control_catalog)
                  .where(control_families: { control_catalog_id: catalog.id })
                  .order(Arel.sql("COALESCE(sort_id, control_id)"))
                  .pluck(:control_id, :label, :title)
                  .map do |control_id, label, title|
                    display = label.presence || control_id
                    [ "#{display} — #{title.to_s.truncate(60)}", control_id ]
                  end
  end

  def set_control_mapping
    @control_mapping = ControlMapping.find_by!(slug: params[:id])
  end

  def load_catalogs
    @catalogs = ControlCatalog.order(:name)
  end

  def control_mapping_params
    params.require(:control_mapping).permit(
      :name, :description, :mapping_version, :oscal_version,
      :status, :method_type, :matching_rationale,
      :source_catalog_id, :target_catalog_id
    )
  end

  def authorize_mapping_write!
    authorize_permission!("mappings.write")
  end
end
