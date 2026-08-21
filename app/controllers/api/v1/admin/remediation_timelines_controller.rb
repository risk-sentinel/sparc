# frozen_string_literal: true

# #809 (D3) — admin-managed remediation-timeline (SLA) table. The Instance Admin
# provisions how many days a team has to remediate, keyed by profile baseline
# level × NIST criticality. Feeds AmendmentValidityService when the boundary's
# profile carries no ODP remediation value for a control.
class Api::V1::Admin::RemediationTimelinesController < Api::V1::BaseController
  before_action :require_admin!

  # GET /api/v1/admin/remediation_timelines — the full grid (provisioned + defaults).
  def index
    rows = grid
    render json: { data: rows, meta: whole_collection(rows) }
  end

  # PUT /api/v1/admin/remediation_timelines — upsert one cell.
  def update
    row = RemediationTimeline.find_or_initialize_by(
      baseline_level: params[:baseline_level], criticality: params[:criticality]
    )
    row.days = params[:days]
    row.updated_by = current_user&.email
    if row.save
      audit_log("remediation_timeline_updated", subject: row,
                metadata: { baseline_level: row.baseline_level, criticality: row.criticality, days: row.days })
      render json: { data: serialize(row) }
    else
      render json: { error: "Validation failed", details: row.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  private

  def require_admin!
    raise NotAuthorizedError, "Admin only" unless current_user&.admin?
  end

  # The effective grid: every baseline × criticality cell, showing the provisioned
  # value or the built-in default and whether it was provisioned.
  def grid
    provisioned = RemediationTimeline.all.index_by { |r| [ r.baseline_level, r.criticality ] }
    RemediationTimeline::BASELINE_LEVELS.flat_map do |baseline|
      RemediationTimeline::CRITICALITIES.map do |criticality|
        row = provisioned[[ baseline, criticality ]]
        {
          baseline_level: baseline,
          criticality: criticality,
          days: row&.days || RemediationTimeline::DEFAULTS.dig(baseline, criticality),
          provisioned: row.present?
        }
      end
    end
  end

  def serialize(row)
    {
      id: row.id, baseline_level: row.baseline_level, criticality: row.criticality,
      days: row.days, updated_by: row.updated_by, updated_at: row.updated_at.utc.iso8601
    }
  end
end
