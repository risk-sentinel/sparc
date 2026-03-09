# frozen_string_literal: true

module Admin
  # Read-only admin interface for viewing and exporting the audit trail.
  # Supports filtering by user, action category, subject type, date range,
  # and free-text search. CSV export for compliance reporting.
  class AuditLogsController < ApplicationController
    include Pagy::Method

    before_action :authorize_admin!

    EVENTS_PER_PAGE = 50

    def index
      scope = AuditEvent.recent.includes(:user)

      # ── Filters ──────────────────────────────────────────────────────
      scope = scope.for_user(User.find(params[:user_id]))   if params[:user_id].present?
      scope = scope.where(action: params[:action_filter])    if params[:action_filter].present?
      scope = scope.by_subject_type(params[:subject_type])   if params[:subject_type].present?
      scope = scope.by_category(params[:category])           if params[:category].present?
      scope = scope.in_date_range(params[:start_date], params[:end_date])
      scope = scope.search(params[:q])                       if params[:q].present?

      respond_to do |format|
        format.html do
          @pagy, @audit_events = pagy(:offset, scope, limit: EVENTS_PER_PAGE)

          # Populate filter dropdowns
          @users          = User.order(:email)
          @categories     = AuditEvent::ACTION_CATEGORIES.keys.sort
          @subject_types  = AuditEvent.where.not(subject_type: nil)
                                      .distinct.pluck(:subject_type).sort
        end
        format.csv do
          csv_data = AuditCsvExportService.new(scope.limit(10_000)).export
          send_data csv_data,
                    filename: "sparc_audit_log_#{Date.today}.csv",
                    type: "text/csv",
                    disposition: "attachment"
        end
      end
    end

    def show
      @audit_event = AuditEvent.find(params[:id])
    end
  end
end
