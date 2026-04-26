# NC/LC discovery UI for the authoritative back-matter library (#372).
# Read-only browse + filter; "use in document" actions go through the
# existing back-matter resource controllers.
class AuthoritativeSourcesController < ApplicationController
  before_action :authorize_read!

  def index
    scope = BackMatterResource.active

    if params[:scope] == "global"
      scope = scope.where(globally_available: true)
    elsif params[:scope] == "authoritative"
      scope = scope.authoritative
    end

    scope = scope.where(rel: params[:rel])               if params[:rel].present?
    scope = scope.where(media_type: params[:media_type]) if params[:media_type].present?

    if params[:q].present?
      term  = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.where("title ILIKE ? OR description ILIKE ?", term, term)
    end

    @resources = scope.order(updated_at: :desc).limit(200)
    @total     = scope.count
  end

  def show
    @resource = BackMatterResource.find(params[:id])
  end

  private

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.read")

    flash[:error] = "Not authorized to view authoritative sources"
    redirect_to root_path
  end
end
