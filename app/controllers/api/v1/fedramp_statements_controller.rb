# frozen_string_literal: true

# #1390 — a boundary's answer to each FedRAMP rule and Key Security Indicator
# (FedrampStatement), which its Security Decision Record carries:
#
#   GET /api/v1/authorization_boundaries/:id/fedramp_statements[?kind=frr|ksi]
#       every rule that applies to the boundary's certification profile (or
#       every KSI), each with its statement (null when not answered)
#   GET /api/v1/authorization_boundaries/:id/fedramp_statements/:kind/:rule_id
#   PUT /api/v1/authorization_boundaries/:id/fedramp_statements/:kind/:rule_id
#       record it: 201 the first time, 200 after; only the fields sent change
#
# 422 when FedRAMP is not enabled for the boundary, for a rule that does not
# apply to it, or for a value the SDR schema does not allow.
#
# Reading needs evidence.read on the boundary, recording evidence.write, or
# an instance administrator. Each change is audited.
#
# NIST SP 800-53: PL-2, CA-2, AC-3 / AC-6, AU-12.
class Api::V1::FedrampStatementsController < Api::V1::BaseController
  include FedrampApiResource

  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show]
  before_action :authorize_write!, only: :update
  before_action :require_fedramp!

  rescue_from FedrampStatementService::Error do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  # GET .../fedramp_statements[?kind=frr|ksi]
  def index
    kind = params[:kind].presence || FedrampRules::FRR
    entries = service.entries(kind)
    type, path, klass = @boundary.fedramp_profile
    render json: {
      data: entries.map { |e| serialize(kind, e.rule, e.statement) },
      meta: { kind: kind, certification_type: type, certification_path: path, certification_class: klass,
              sdr_version: @boundary.fedramp_sdr_version, rules_version: FedrampRules.version,
              total: entries.size, answered: entries.count(&:statement) }
    }
  end

  # GET .../fedramp_statements/:kind/:rule_id
  def show
    rule = service.find!(params[:kind], params[:rule_id])
    statement = @boundary.fedramp_statements.find_by(kind: params[:kind], rule_id: rule.id)
    render json: { data: serialize(params[:kind], rule, statement) }
  end

  # PUT .../fedramp_statements/:kind/:rule_id
  def update
    result = service.record(kind: params[:kind], rule_id: params[:rule_id], attributes: statement_params,
                            user: current_user)
    audit_log("fedramp_statement_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, kind: params[:kind], rule_id: params[:rule_id],
                          created: result.created, changed: result.changes, status: result.statement.status })
    render json: { data: serialize(params[:kind], service.find!(params[:kind], params[:rule_id]), result.statement) },
           status: result.created ? :created : :ok
  end

  private

  def service = (@service ||= FedrampStatementService.new(@boundary))

  def statement_params
    # FedrampStatementService::FIELDS and KSI_FIELDS, spelled out so
    # bin/api_postman_check.rb can read the body this endpoint takes.
    permit_strictly(:fedramp_statement, :status, :implementation, :validation, :assessment,
                    tests: [], evidence: FedrampStatement::EVIDENCE_KEYS).to_h
  end

  def serialize(kind, rule, statement)
    base = { kind: kind, rule_id: rule.id, name: rule.name, statement: rule.statement }
    base.merge!(kind == FedrampRules::KSI ? { theme: rule.theme, controls: rule.controls } : { family: rule.family, force: rule.force })
    base.merge(answer: statement && {
      status: statement.status, implementation: statement.implementation, validation: statement.validation,
      assessment: statement.assessment, tests: statement.tests, evidence: statement.evidence,
      updated_at: statement.updated_at&.iso8601, updated_by_id: statement.updated_by_id
    })
  end

  def authorize_read!
    authorize_boundary_permission!("evidence.read", "Not authorized to read this boundary's FedRAMP statements")
  end

  def authorize_write!
    authorize_boundary_permission!("evidence.write", "Not authorized to record this boundary's FedRAMP statements")
  end
end
