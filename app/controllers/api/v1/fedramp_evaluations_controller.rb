# frozen_string_literal: true

# #1354 / #1384 — the provider's FedRAMP evaluation of each vulnerability in a
# boundary, keyed by the finding's control_id (FedRAMP's tracking identifier:
# the one key that stays the same across scans).
#
#   GET /api/v1/authorization_boundaries/:authorization_boundary_id/fedramp_evaluations
#         ?unevaluated=true   the current failing findings with no evaluation yet
#   GET /api/v1/authorization_boundaries/:authorization_boundary_id/fedramp_evaluations/:control_id
#   PUT /api/v1/authorization_boundaries/:authorization_boundary_id/fedramp_evaluations/:control_id
#
# A control_id can hold dots (XCCDF rule ids) and slashes (package URLs); a
# slash is sent percent-encoded (%2F), and the route takes the whole segment.
#
# PUT is an upsert through FedrampEvaluationService, the path the triage
# screen takes too: 201 when the first evaluation is recorded, 200 after; 422
# for a control the boundary has no failing finding for, or a value FedRAMP's
# fields cannot hold (an N-rating outside N0–N5, a next reduction that is not
# lower than the current rating).
#
# Permissions, on the boundary: read evidence.read, write evidence.write (the
# same as the triage dispositions next to it).
#
# NIST SP 800-53: IA-2 (token auth), AC-3 / AC-6 (boundary-scoped
# permissions), RA-3 (risk assessment), RA-5 (vulnerability monitoring),
# AU-12 (each evaluation recorded is audited).
class Api::V1::FedrampEvaluationsController < Api::V1::BaseController
  NOT_FOUND_BODY = { error: "Not found" }.freeze

  include RequiresFedramp

  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show]
  before_action :authorize_write!, only: %i[update]
  before_action :require_fedramp!

  rescue_from FedrampEvaluationService::Error do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  # GET .../fedramp_evaluations[?unevaluated=true]
  def index
    if params[:unevaluated] == "true"
      result = paginate(unevaluated_findings)
      data = result[:data].map { |finding| serialize(unevaluated(finding.control_id)) }
    else
      result = paginate(@boundary.fedramp_vulnerability_evaluations.includes(:evaluated_by).order(:control_id))
      data = result[:data].map { |evaluation| serialize(evaluation) }
    end
    render json: { data: data, meta: result[:meta] }
  end

  # GET .../fedramp_evaluations/:control_id — a detected vulnerability not yet
  # evaluated answers 200 with `evaluated: false`; a control with no failing
  # finding and no evaluation is 404.
  def show
    evaluation = @boundary.fedramp_vulnerability_evaluations.find_by(control_id: params[:control_id])
    if evaluation.nil?
      return render(json: NOT_FOUND_BODY, status: :not_found) unless detected?(params[:control_id])

      evaluation = unevaluated(params[:control_id])
    end
    render json: { data: serialize(evaluation) }
  end

  # PUT .../fedramp_evaluations/:control_id
  def update
    result = FedrampEvaluationService.new(@boundary).record(
      control_id: params[:control_id], attributes: evaluation_params, user: current_user
    )
    evaluation = result.evaluation
    audit_log("fedramp_evaluation_recorded", subject: evaluation,
              metadata: { authorization_boundary_id: @boundary.id, control_id: evaluation.control_id,
                          created: result.created, changed: result.changes,
                          pain_rating: evaluation.pain_rating })
    render json: { data: serialize(evaluation) }, status: result.created ? :created : :ok
  end

  private

  def set_boundary
    key = params[:authorization_boundary_id].to_s
    @boundary =
      if key.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  def evaluation_params
    # FedrampEvaluationService::FIELDS, spelled out so bin/api_postman_check.rb
    # can read the body this endpoint takes.
    permit_strictly(
      :fedramp_evaluation, :internet_reachable, :likely_exploitable, :pain_rating, :evaluated_at,
      :next_reduction_at, :next_reduction_rating, :supplementary_info
    ).to_h
  end

  # An unsaved evaluation, so a vulnerability not yet evaluated reads in the
  # same shape as one that has been (`evaluated: false`, every field null).
  def unevaluated(control_id)
    FedrampVulnerabilityEvaluation.new(authorization_boundary: @boundary, control_id: control_id)
  end

  def detected?(control_id)
    @boundary.scanner_findings.failed.exists?(control_id: control_id)
  end

  # One row per control among the current failing findings with no evaluation.
  def unevaluated_findings
    evaluated = @boundary.fedramp_vulnerability_evaluations.select(:control_id)
    firsts = @boundary.scanner_findings.current.failed.where.not(control_id: evaluated)
                      .group(:control_id).select("MIN(scanner_findings.id)")
    ScannerFinding.where(id: firsts).order(:control_id)
  end

  def person(user)
    user && { id: user.id, name: user.display_name.presence || user.email }
  end

  def iso(time) = time&.utc&.iso8601

  def serialize(evaluation)
    current = evaluation.current_finding
    {
      id: evaluation.id,
      uuid: evaluation.uuid,
      authorization_boundary_id: evaluation.authorization_boundary_id,
      control_id: evaluation.control_id,
      evaluated: evaluation.evaluated?,
      evaluated_at: iso(evaluation.evaluated_at),
      evaluated_by: person(evaluation.evaluated_by),
      internet_reachable: evaluation.internet_reachable,
      likely_exploitable: evaluation.likely_exploitable,
      pain_rating: evaluation.pain_rating,
      pain_label: FedrampVulnerabilityEvaluation.pain_label(evaluation.pain_rating),
      pain_history: Array(evaluation.pain_history),
      pain_reductions: evaluation.pain_reductions,
      next_reduction_at: iso(evaluation.next_reduction_at),
      next_reduction_rating: evaluation.next_reduction_rating,
      supplementary_info: evaluation.supplementary_info,
      detected_at: iso(evaluation.detected_at),
      current_finding: current && { uuid: current.uuid, status: current.status, severity: current.severity,
                                    title: current.title, scanner: current.scanner },
      created_at: iso(evaluation.created_at),
      updated_at: iso(evaluation.updated_at)
    }
  end

  def authorize_read!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("evidence.read", authorization_boundary_id: @boundary.id)

    raise NotAuthorizedError, "Not authorized to view this boundary's FedRAMP evaluations"
  end

  def authorize_write!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("evidence.write", authorization_boundary_id: @boundary.id)

    raise NotAuthorizedError, "Not authorized to record FedRAMP evaluations on this boundary"
  end
end
