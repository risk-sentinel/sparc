class HomeController < ApplicationController
  def index
    @project_count = Project.count
    @ssp_count     = SspDocument.count
    @sar_count     = SarDocument.count
    @catalog_count = ControlCatalog.count
    @family_count  = ControlFamily.count
    @control_count = CatalogControl.count
    @cdef_count = CdefDocument.count
    @profile_count = ProfileDocument.count
    @sap_count     = SapDocument.count
    @poam_count    = PoamDocument.count
    @evidence_count = Evidence.count

    # Aggregate compliance heatmap across all SSP documents
    @heatmap_data, @heatmap_families, @heatmap_statuses =
      DashboardAggregationService.new.call
  end

  def family_drilldown
    @family = params[:family].to_s.gsub(/[^A-Za-z]/, "").upcase
    @controls = SspControl
      .joins(:ssp_document)
      .where("UPPER(SPLIT_PART(ssp_controls.control_id, '-', 1)) = ?", @family)
      .includes(:ssp_control_fields, :ssp_document)
      .order(:control_id)
  end
end
