# frozen_string_literal: true

# #860 — the unmatched-grant queue, on screen.
#
# A thin client over the same UnmatchedGrantQuery the API and the daily digest
# read, so the screen, the endpoint and the email cannot disagree about what is
# outstanding.
class Admin::IdpGrantsController < ApplicationController
  before_action :authorize_admin!

  DEFAULT_WINDOW_DAYS = 30

  def index
    @window_days = (params[:days].presence&.to_i || DEFAULT_WINDOW_DAYS).clamp(1, 365)
    query = UnmatchedGrantQuery.new(window: @window_days.days)
    @summary = query.summary
    @events = query.events.includes(:user).limit(200)
  end
end
