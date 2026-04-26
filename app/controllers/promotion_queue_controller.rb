# NC/LC promotion queue UI (#372). Lists pending promotions the current
# user is authorized to approve, with inline approve / reject actions.
# Both actions call BackMatterResourcePromotionService — same code path
# the API uses.
class PromotionQueueController < ApplicationController
  before_action :set_resource, only: %i[approve reject]

  def index
    pending = BackMatterResource.pending_promotion.includes(:resourceable, :organization)
    @resources = pending.select do |r|
      BackMatterResourcePromotionService.new(resource: r, actor: current_user).can_approve?
    end
  end

  def approve
    result = BackMatterResourcePromotionService.new(resource: @resource, actor: current_user).approve!

    if result.success?
      audit_log("back_matter_resource_promotion_approved", subject: @resource,
                metadata: { title: @resource.title })
      flash[:success] = "Promoted \"#{@resource.title}\" to authoritative"
    else
      flash[:error] = result.error || "Could not approve"
    end
    redirect_to promotion_queue_index_path
  end

  def reject
    reason = params[:reason]
    result = BackMatterResourcePromotionService.new(resource: @resource, actor: current_user)
                                               .reject!(reason: reason)
    if result.success?
      audit_log("back_matter_resource_promotion_rejected", subject: @resource,
                metadata: { title: @resource.title })
      flash[:success] = "Rejected \"#{@resource.title}\""
    else
      flash[:error] = result.error || "Could not reject"
    end
    redirect_to promotion_queue_index_path
  end

  private

  def set_resource
    @resource = BackMatterResource.find(params[:id])
  end
end
