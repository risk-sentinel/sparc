class HomeController < ApplicationController
  def index
    @authorization_boundary_count = AuthorizationBoundary.count
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
  end
end
