class HomeController < ApplicationController
  def index
    @ssp_count     = SspDocument.count
    @sar_count     = SarDocument.count
    @catalog_count = ControlCatalog.count
    @family_count  = ControlFamily.count
    @control_count = CatalogControl.count
    @cdef_count = CdefDocument.count
  end
end
