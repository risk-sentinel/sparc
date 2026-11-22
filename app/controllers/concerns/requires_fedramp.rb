# frozen_string_literal: true

# #1390 — FedRAMP is something a boundary turns on (fedramp_enabled). Until it
# does, its FedRAMP features are refused: the API answers 422, a page goes
# back to the boundary with the reason. One definition for every FedRAMP
# controller. Include after the boundary is loaded and authorized:
#
#   before_action :require_fedramp!
module RequiresFedramp
  extend ActiveSupport::Concern

  NOT_ENABLED = "FedRAMP is not enabled for this boundary. Turn it on in the boundary's FedRAMP section " \
                "(fedramp_enabled) to use its FedRAMP features."

  private

  def require_fedramp!
    return if @boundary.fedramp_enabled?

    if is_a?(Api::V1::BaseController)
      render json: { error: NOT_ENABLED }, status: :unprocessable_content
    else
      redirect_to authorization_boundary_path(@boundary), error: NOT_ENABLED
    end
  end
end
