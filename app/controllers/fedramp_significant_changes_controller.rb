# frozen_string_literal: true

# #1390 — the Significant changes tab of the boundary's FedRAMP page: every
# change the provider evaluated (Routine, Adaptive, Transformative), the
# notices each needs and when, and its Significant Change Notification. A thin
# client of FedrampSignificantChangeService, the same service as
# Api::V1::FedrampSignificantChangesController.
#
#   GET   /authorization_boundaries/:id/fedramp/changes
#   POST  /authorization_boundaries/:id/fedramp/changes
#   GET   /authorization_boundaries/:id/fedramp/changes/:change_id
#   PATCH /authorization_boundaries/:id/fedramp/changes/:change_id
#   GET   /authorization_boundaries/:id/fedramp/changes/:change_id/notification
#   POST  /authorization_boundaries/:id/fedramp/changes/:change_id/notices
#
# The page is the notification in human-readable form, the download its JSON
# (SCN-CSO-HRM). Reading needs evidence.read on the boundary, recording
# evidence.write. FedRAMP must be turned on for the boundary.
#
# NIST SP 800-53: CM-3, CM-4, AC-3 / AC-6, AU-12 (each change audited).
class FedrampSignificantChangesController < ApplicationController
  include FedrampPage

  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show notification]
  before_action :authorize_write!, only: %i[create update record_notice]
  before_action :require_fedramp!
  before_action :set_change, only: %i[show update notification record_notice]

  def index
    @changes = service.changes.to_a
    @change = @boundary.fedramp_significant_changes.new(change_type: FedrampSignificantChange::ADAPTIVE)
    @may_edit = boundary_permission?("evidence.write")
  end

  def show
    @deadlines = service.deadlines(@change)
    @may_edit = boundary_permission?("evidence.write")
  end

  def create
    result = service.record(attributes: change_params, user: current_user)
    audit(result)
    redirect_to fedramp_significant_change_authorization_boundary_path(@boundary, result.change),
                success: "Recorded the #{result.change.change_type.downcase} change."
  rescue FedrampSignificantChangeService::Error => e
    redirect_to fedramp_significant_changes_authorization_boundary_path(@boundary), error: "Change not recorded: #{e.message}"
  end

  def update
    result = service.record(change: @change, attributes: change_params, user: current_user)
    audit(result)
    redirect_to fedramp_significant_change_authorization_boundary_path(@boundary, @change), success: "Saved the change."
  rescue FedrampSignificantChangeService::Error => e
    redirect_to fedramp_significant_change_authorization_boundary_path(@boundary, @change), error: "Change not saved: #{e.message}"
  end

  def notification
    doc = service.notification(@change)
    audit_log("fedramp_significant_change_notification_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, change: @change.uuid, change_type: @change.change_type })
    send_data JSON.pretty_generate(doc), filename: "#{@boundary.slug || @boundary.uuid}-fedramp-scn-#{@change.uuid}.json",
                                         type: "application/json", disposition: "attachment"
  rescue FedrampSignificantChangeService::Error, FedrampVulnerabilityReportService::Error => e
    redirect_to fedramp_significant_change_authorization_boundary_path(@boundary, @change),
                error: "Notification not produced: #{e.message}"
  end

  def record_notice
    notice = service.record_notice(@change, stage: params[:stage], sent_on: params[:sent_on], user: current_user)
    audit_log("fedramp_significant_change_notice_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, change: @change.uuid, stage: notice["stage"],
                          rule_id: notice["rule_id"], sent_on: notice["sent_on"], sha256: notice["sha256"] }.compact)
    redirect_to fedramp_significant_change_authorization_boundary_path(@boundary, @change),
                success: "Recorded the notice sent on #{notice['sent_on']}."
  rescue FedrampSignificantChangeService::Error, FedrampVulnerabilityReportService::Error => e
    redirect_to fedramp_significant_change_authorization_boundary_path(@boundary, @change),
                error: "Notice not recorded: #{e.message}"
  end

  private

  def service = (@service ||= FedrampSignificantChangeService.new(@boundary))

  def set_change
    @change = service.find!(params[:change_id])
  end

  def change_params
    params.fetch(:fedramp_significant_change, {})
          .permit(*(FedrampSignificantChangeService::FIELDS - %w[milestones]),
                  milestones: FedrampSignificantChange::MILESTONE_KEYS).to_h
          .tap { |h| h["milestones"] = [] if params[:milestones_listed].present? && !h.key?("milestones") }
  end

  def audit(result)
    audit_log("fedramp_significant_change_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, change: result.change.uuid,
                          change_type: result.change.change_type, created: result.created, changed: result.changes })
  end

  def authorize_read!
    authorize_permission!("evidence.read", authorization_boundary_id: @boundary.id)
  end

  def authorize_write!
    authorize_permission!("evidence.write", authorization_boundary_id: @boundary.id)
  end
end
