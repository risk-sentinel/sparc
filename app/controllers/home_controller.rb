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
  end
end
