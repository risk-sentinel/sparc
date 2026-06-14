# frozen_string_literal: true

# Shared UI plumbing for index-page bulk delete (#629). Runs BulkDestroyService
# and renders a partial-success flash summary (deleted / blocked-with-reason).
# API controllers don't use this — they render the service result as JSON.
#
# Including controllers gate the bulk action with `authorize_admin!`.
module BulkDestroyable
  extend ActiveSupport::Concern

  private

  def perform_bulk_destroy(model_class:, redirect_path:, label:)
    result = BulkDestroyService.new(
      model_class: model_class,
      ids:         params[:ids],
      user:        current_user,
      ip_address:  request.remote_ip
    ).call

    message = result.summary_sentence(label)
    if result.blocked.any?
      message += " Blocked: " + result.blocked.map { |b| "#{b[:name]} — #{b[:reason]}" }.join("; ")
    end

    level = if result.deleted.empty? && (result.blocked.any? || result.missing.any?)
              :error
    elsif result.blocked.any?
              :warning
    else
              :success
    end

    flash[level] = message
    redirect_to redirect_path
  end
end
