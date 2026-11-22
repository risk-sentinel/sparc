# frozen_string_literal: true

# #1390 — the boundary's FedRAMP page: every FedRAMP rule that applies to its
# certification profile, and every Key Security Indicator, each with the
# boundary's answer (FedrampStatement), which its Security Decision Record
# carries. A thin client of FedrampStatementService, the same service as
# Api::V1::FedrampStatementsController.
#
#   GET   /authorization_boundaries/:id/fedramp[?kind=frr|ksi]
#   PATCH /authorization_boundaries/:id/fedramp/statements/:kind/:rule_id
#
# Reading needs evidence.read on the boundary, recording evidence.write (as a
# FedRAMP evaluation does). FedRAMP must be turned on for the boundary.
#
# NIST SP 800-53: PL-2, CA-2, AC-3 / AC-6 (boundary-scoped permission),
# AU-12 (each change audited).
class FedrampStatementsController < ApplicationController
  include RequiresFedramp

  before_action :set_boundary
  before_action :authorize_read!, only: :index
  before_action :authorize_write!, only: :update
  before_action :require_fedramp!

  def index
    @kind = FedrampRules::KINDS.include?(params[:kind]) ? params[:kind] : FedrampRules::FRR
    service = FedrampStatementService.new(@boundary)
    @entries = service.entries(@kind)
    @counts = FedrampRules::KINDS.index_with { |k| k == @kind ? @entries.size : service.entries(k).size }
    @summary = @entries.group_by(&:status).transform_values(&:size)
    @sdr_gaps = FedrampSecurityDecisionRecordService.new(@boundary).gaps
    @may_edit = !SparcConfig.any_auth_enabled? ||
                current_user&.has_permission?("evidence.write", authorization_boundary_id: @boundary.id)
  end

  def update
    kind = params[:kind]
    result = FedrampStatementService.new(@boundary).record(
      kind: kind, rule_id: params[:rule_id], user: current_user,
      attributes: statement_params.to_h.merge(tests_from_lines)
    )
    audit_log("fedramp_statement_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, kind: kind, rule_id: params[:rule_id],
                          created: result.created, changed: result.changes, status: result.statement.status })
    redirect_to fedramp_authorization_boundary_path(@boundary, kind: kind, anchor: anchor),
                success: "Saved #{params[:rule_id]}."
  rescue FedrampStatementService::Error => e
    redirect_to fedramp_authorization_boundary_path(@boundary, kind: kind, anchor: anchor),
                error: "#{params[:rule_id]} not saved: #{e.message}"
  end

  private

  def anchor = "fedramp-#{params[:rule_id]}"

  def statement_params
    params.fetch(:fedramp_statement, {}).permit(*FedrampStatementService::FIELDS,
                                                evidence: FedrampStatement::EVIDENCE_KEYS)
  end

  # The form takes a KSI's tests one per line, and marks its evidence list so
  # removing every row clears it.
  def tests_from_lines
    form = params.fetch(:fedramp_statement, {})
    extra = {}
    extra["tests"] = form[:tests_text].to_s.lines.map(&:strip) unless form[:tests_text].nil?
    extra["evidence"] = [] if form[:evidence_listed].present? && form[:evidence].nil?
    extra
  end

  def set_boundary
    key = params[:id]
    @boundary = key.to_s.match?(/\A\d+\z/) ? AuthorizationBoundary.find(key) : AuthorizationBoundary.find_by!(slug: key)
  end

  def authorize_read!
    authorize_permission!("evidence.read", authorization_boundary_id: @boundary.id)
  end

  def authorize_write!
    authorize_permission!("evidence.write", authorization_boundary_id: @boundary.id)
  end
end
