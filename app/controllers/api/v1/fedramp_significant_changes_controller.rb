# frozen_string_literal: true

# #1390 — a boundary's FedRAMP significant changes (FedrampSignificantChange):
#
#   GET  /api/v1/authorization_boundaries/:id/fedramp_significant_changes
#   POST /api/v1/authorization_boundaries/:id/fedramp_significant_changes
#   GET  /api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id
#   PUT  /api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id
#        only the fields sent change
#   GET  .../fedramp_significant_changes/:change_id/notification
#        the Significant Change Notification (SCN-CSO-INF), validated
#   POST .../fedramp_significant_changes/:change_id/notices   { stage, sent_on }
#        records a notice sent, with the notification as it stood
#
# Each change carries its notices with when each is due (federal business
# days). 422 when FedRAMP is not enabled for the boundary, for a value the
# record does not allow, or for a routine change's notification. Reading needs
# evidence.read on the boundary, recording evidence.write, or an instance
# administrator. Each change is audited.
#
# NIST SP 800-53: CM-3, CM-4, AC-3 / AC-6, AU-12.
class Api::V1::FedrampSignificantChangesController < Api::V1::BaseController
  include FedrampApiResource

  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show notification]
  before_action :authorize_write!, only: %i[create update record_notice]
  before_action :require_fedramp!
  before_action :set_change, only: %i[show update notification record_notice]

  rescue_from FedrampSignificantChangeService::Error do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  rescue_from FedrampVulnerabilityReportService::MissingPackageOverview do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  rescue_from FedrampVulnerabilityReportService::InvalidReport do |e|
    render json: { error: e.message, errors: e.errors }, status: :bad_gateway
  end

  def index
    changes = service.changes.to_a
    render json: { data: changes.map { |c| serialize(c) },
                   meta: { total: changes.size, notifiable: changes.count { |c| !c.routine? } } }
  end

  def show
    render json: { data: serialize(@change) }
  end

  def create
    result = service.record(attributes: change_params, user: current_user)
    audit(result)
    render json: { data: serialize(result.change) }, status: :created
  end

  def update
    result = service.record(change: @change, attributes: change_params, user: current_user)
    audit(result)
    render json: { data: serialize(result.change) }
  end

  def notification
    doc = service.notification(@change)
    audit_log("fedramp_significant_change_notification_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, change: @change.uuid, change_type: @change.change_type })
    render json: doc
  end

  def record_notice
    body = permit_strictly(:notice, :stage, :sent_on)
    notice = service.record_notice(@change, stage: body[:stage], sent_on: body[:sent_on], user: current_user)
    audit_log("fedramp_significant_change_notice_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, change: @change.uuid, stage: notice["stage"],
                          rule_id: notice["rule_id"], sent_on: notice["sent_on"], sha256: notice["sha256"] }.compact)
    render json: { data: serialize(@change.reload) }, status: :created
  end

  private

  def service = (@service ||= FedrampSignificantChangeService.new(@boundary))

  def set_change
    @change = service.find!(params[:change_id])
  end

  def change_params
    # FedrampSignificantChangeService::FIELDS, spelled out so
    # bin/api_postman_check.rb can read the body this endpoint takes.
    permit_strictly(:fedramp_significant_change, :change_type, :description, :type_explanation, :reason,
                    :customer_impact, :plan_summary, :planned_start, :planned_completion, :impact_analysis,
                    :assessor_name, :related_vulnerability, :approver_name, :approver_title, :new_risks,
                    :emergency, :started_on, :finished_on, :verified_on,
                    impacted_controls: [], milestones: FedrampSignificantChange::MILESTONE_KEYS).to_h
  end

  def serialize(change)
    change.as_json(only: %w[uuid change_type description type_explanation reason customer_impact plan_summary
                            planned_start planned_completion milestones impacted_controls impact_analysis
                            assessor_name related_vulnerability approver_name approver_title new_risks emergency
                            started_on finished_on verified_on created_at updated_at created_by_id updated_by_id])
          .merge("notices" => Array(change.notices).map { |n| n.except("document") },
                 "deadlines" => service.deadlines(change).map do |d|
                   { stage: d.key, rule_id: d.rule_id, label: d.label, due_on: d.due_on&.iso8601,
                     timeframe: d.timeframe, retroactive: d.retroactive, status: d.status, sent_on: d.sent_on&.iso8601 }
                 end)
  end

  def audit(result)
    audit_log("fedramp_significant_change_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, change: result.change.uuid,
                          change_type: result.change.change_type, created: result.created, changed: result.changes })
  end

  def authorize_read!
    authorize_boundary_permission!("evidence.read", "Not authorized to read this boundary's significant changes")
  end

  def authorize_write!
    authorize_boundary_permission!("evidence.write", "Not authorized to record this boundary's significant changes")
  end
end
