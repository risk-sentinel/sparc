# #396: CRUD for LeveragedAuthorization records on an authorization
# boundary. The wizard supports three scenarios:
#
#   1. oscal_with_access — pick another AuthorizationBoundary in the same
#      organization; auto-populates inheritance links from its SSP
#   2. oscal_no_access   — upload an OSCAL-format CRM/SSRM back-matter
#   3. legacy            — upload a legacy (non-OSCAL) CRM back-matter
class LeveragedAuthorizationsController < ApplicationController
  before_action :set_leveraging_boundary
  before_action :authorize_leveraging_boundary
  before_action :set_leveraged_authorization, only: [ :show, :destroy, :populate ]

  def new
    @leveraged_authorization = @leveraging_boundary.leveraging_relationships.new
    @candidate_boundaries = candidate_boundaries
  end

  def create
    @leveraged_authorization = @leveraging_boundary.leveraging_relationships.new(la_params)
    if @leveraged_authorization.save
      if @leveraged_authorization.scenario == 1
        LeveragedAuthorizationService.populate_from_leveraged!(@leveraged_authorization)
      end
      redirect_to authorization_boundary_path(@leveraging_boundary),
                  notice: "Leveraged authorization created."
    else
      @candidate_boundaries = candidate_boundaries
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def destroy
    @leveraged_authorization.destroy
    redirect_to authorization_boundary_path(@leveraging_boundary),
                notice: "Leveraged authorization removed."
  end

  # Idempotent re-population of inheritance links from the leveraged SSP.
  # Useful when the leveraged system's prose has been updated and the
  # leveraging side wants a fresh import.
  def populate
    count = LeveragedAuthorizationService.populate_from_leveraged!(@leveraged_authorization)
    redirect_to authorization_boundary_path(@leveraging_boundary),
                notice: "Populated #{count} inheritance link(s) from the leveraged SSP."
  end

  private

  def set_leveraging_boundary
    @leveraging_boundary = AuthorizationBoundary.find(params[:authorization_boundary_id])
  end

  def set_leveraged_authorization
    @leveraged_authorization = @leveraging_boundary.leveraging_relationships.find(params[:id])
  end

  def authorize_leveraging_boundary
    return if current_user&.admin?

    unless @leveraging_boundary.assigned_users.exists?(id: current_user&.id)
      redirect_to authorization_boundaries_path,
                  alert: "You don't have permission to modify this boundary."
    end
  end

  def la_params
    params.require(:leveraged_authorization).permit(
      :name, :crm_type, :leveraged_boundary_id, :date_authorized, :description
    )
  end

  # Same-org boundaries that aren't this one. Cross-org sharing is a
  # future enhancement per the plan's risk section.
  def candidate_boundaries
    scope = AuthorizationBoundary.where.not(id: @leveraging_boundary.id)
    if @leveraging_boundary.organization_id
      scope = scope.where(organization_id: @leveraging_boundary.organization_id)
    end
    scope.order(:name)
  end
end
