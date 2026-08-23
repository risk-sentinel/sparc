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
    @hints = @summary.to_h do |row|
      [ row[:example_grant], UnmatchedGrantResolutionHint.new(row[:example_grant]).hint ]
    end
    @dismissed = DismissedIdpGrant.order(created_at: :desc).includes(:dismissed_by)
  end

  # Stop reporting a grant that is simply wrong — a group misnamed in the IdP,
  # a boundary that will never exist. Changes no access: the grant was already
  # refused when it arrived.
  def dismiss
    grant = params.require(:grant)
    record = DismissedIdpGrant.find_or_initialize_by(grant: IdpGrant.canonicalize(grant))
    record.assign_attributes(dismissed_by: current_user, reason: params[:reason].presence)
    record.save!

    AuditEvent.log(user: current_user, action: "idp_grant_dismissed", provider: "oidc",
                   ip_address: request.remote_ip,
                   metadata: { grant: record.grant, reason: record.reason })

    redirect_to admin_idp_grants_path, success: "#{record.grant} will no longer be reported."
  end

  # Not a one-way door. Restoring it means the next sign-in carrying the grant
  # reports it again.
  def restore
    record = DismissedIdpGrant.find(params[:id])
    grant = record.grant
    record.destroy!

    AuditEvent.log(user: current_user, action: "idp_grant_dismissal_restored", provider: "oidc",
                   ip_address: request.remote_ip, metadata: { grant: grant })

    redirect_to admin_idp_grants_path, success: "#{grant} will be reported again."
  end
end
