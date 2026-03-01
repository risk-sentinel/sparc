class HomeController < ApplicationController
  def index
    @ssp_count     = SspDocument.count
    @tpr_count     = TprDocument.count
    @catalog_count = ControlCatalog.count
    @family_count  = ControlFamily.count
    @control_count = CatalogControl.count
  end
end