# frozen_string_literal: true

# Keeps a SAR control's risk in step with what is known about the control.
# The POA&M is built from SAR risks (PoamGeneratorService), so this is what
# decides whether a weakness reaches it.
#
# The control's risk is OPEN while any of these holds, and CLOSED otherwise:
#
#   - an 800-53A objective of the control is determined `failed`;
#   - the control's own result is `Failed` (a catalog without 800-53A
#     objectives, Rev 4 among them, is assessed per control);
#   - the SSP itself reports the control "Deferred" or "Will Not Implement"
#     (SarFromSspService's known finding, owner 2026-10-21).
#
# Each failure is a not-satisfied finding linked to the risk: an objective-id
# target for an objective, a statement-id target (`ac-1_smt`) for the control.
#
# Run from SarControlObjective and SarControlField callbacks, so the web form,
# the API, field-file import and the reference estate cannot disagree:
# recording a failure used to change a status and nothing else, and an
# assessed failure never reached the POA&M.
#
# One risk per control, named as SarFromSspService names a known risk.
#
# NIST 800-53: CA-2, CA-5 (plan of action and milestones), CA-7.
class SarControlRiskSync
  NOT_SATISFIED = "not-satisfied"
  FAILED_RESULT = "Failed"

  def initialize(control)
    @control = control
    @document = control.sar_document
  end

  def sync!
    return if result.nil?

    failed_objectives = @control.sar_control_objectives.where(status: "failed").order(:row_order).to_a.reject(&:container?)
    control_failed = field("result") == FAILED_RESULT
    known = SarFromSspService::KNOWN_NOT_IMPLEMENTED.include?(field("ssp_status"))
    risk = result.sar_risks.find_by(uuid: risk_uuid)

    unless failed_objectives.any? || control_failed || known
      risk&.update!(status: "closed")
      return
    end

    reasons = failed_objectives.map { |o| "#{o.label.presence || o.objective_id} #{o.prose}".strip }
    reasons << "the control as a whole was assessed #{FAILED_RESULT}" if control_failed
    attrs = { status: "open" }
    if failed_objectives.any? || control_failed
      attrs[:description] = "#{@control.control_id} was assessed not satisfied."
      attrs[:statement] = "#{@control.control_id} does not satisfy: #{reasons.join('; ')}"
    end

    risk ||= result.sar_risks.create!(uuid: risk_uuid, title: "Risk for #{@control.control_id}",
                                      description: attrs[:description] || "#{@control.control_id} is not implemented.",
                                      statement: attrs[:statement] || "#{@control.control_id} is reported not implemented.",
                                      status: "open")
    risk.update!(attrs)

    failed_objectives.each { |objective| link!(risk, objective_finding(objective)) }
    link!(risk, control_finding) if control_failed
  end

  private

  def field(name) = @control.sar_control_fields.find_by(field_name: name)&.field_value

  def link!(risk, finding) = SarFindingRisk.find_or_create_by!(sar_finding: finding, sar_risk: risk)

  def objective_finding(objective)
    result.sar_findings.find_or_create_by!(
      uuid: OscalUuidService.derived(result.uuid, "sar-objective-finding", objective.objective_id)
    ) do |f|
      f.title = "Finding for #{objective.label.presence || objective.objective_id}"
      f.description = objective.prose.presence || "Determination for #{objective.objective_id}"
      f.target_data = { "type" => "objective-id", "target-id" => objective.objective_id,
                        "status" => { "state" => NOT_SATISFIED } }
    end
  end

  def control_finding
    statement_id = "#{ControlId.canonical(@control.control_id)}_smt"
    result.sar_findings.find_or_create_by!(
      uuid: OscalUuidService.derived(result.uuid, "sar-control-finding", statement_id)
    ) do |f|
      f.title = "Finding for #{@control.control_id}"
      f.description = "#{@control.control_id} was assessed #{FAILED_RESULT}."
      f.target_data = { "type" => "statement-id", "target-id" => statement_id,
                        "status" => { "state" => NOT_SATISFIED } }
    end
  end

  # The SAR's first result, where SAR generation puts its findings and risks.
  def result
    @result ||= @document.sar_results.order(:position, :id).first
  end

  def risk_uuid
    OscalUuidService.derived(result.uuid, "sar-risk", ControlId.canonical(@control.control_id))
  end
end
