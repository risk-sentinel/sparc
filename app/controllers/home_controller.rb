class HomeController < ApplicationController
  def index
    # Controls Layer
    @catalog_count = ControlCatalog.count
    @family_count  = ControlFamily.distinct.count(:code)
    @control_count = CatalogControl.distinct.count(:control_id)
    @profile_count = ProfileDocument.count
    @mapping_count = ControlMapping.count

    # Implementation Layer
    @ssp_count       = SspDocument.count
    @cdef_count      = CdefDocument.count
    @converter_count = Converter.count

    # Assessment Layer
    @sap_count      = SapDocument.count
    @sar_count      = SarDocument.count
    @evidence_count = Evidence.count
    @poam_count     = PoamDocument.count

    # Enterprise
    @organization_count = Organization.count
    @authorization_boundary_count = AuthorizationBoundary.count
  end

  def oscal_overview
    # Static informational page: renders its template, no data to load.
  end
end
