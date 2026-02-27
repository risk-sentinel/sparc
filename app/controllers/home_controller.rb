class HomeController < ApplicationController
  def index
    @ssp_count = SspDocument.count
    @tpr_count = TprDocument.count
  end
end