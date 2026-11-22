# frozen_string_literal: true

# #1390 — a boundary's FedRAMP significant changes (FedrampSignificantChange):
# recording each one evaluated, the notices FedRAMP requires and when each is
# due, and the Significant Change Notification (SCN-CSO-INF) itself, validated
# against FedRAMP's pinned schema before it is returned. The boundary's
# FedRAMP page and Api::V1::FedrampSignificantChangesController are thin
# clients of it.
#
# The notices, and the FedRAMP rule that sets each deadline (business days
# are federal business days, FederalBusinessDays; the counts are read from
# the rules file):
#
#   Transformative  initial plans       SCN-TRF-NIP  30 before the start
#                   final plans         SCN-TRF-NFP  10 before the start
#                   after finishing     SCN-TRF-NAF   5 after the finish
#                   after verification  SCN-TRF-NAV   5 after verification
#                   updated documents   SCN-TRF-UPD  30 after the finish
#   Adaptive        after finishing     SCN-ADP-NTF  10 after the finish
#   Routine         none (SCN-RTR-NNR); the change is recorded as evaluated
#
# The start is the actual start once recorded, else the planned start. A
# change made in an emergency (SCN-CSO-EMG) gives its before-start notices
# afterwards, by the after-finishing deadline.
#
# NIST SP 800-53: CM-3, CM-4, CA-7, AU-12 (the controllers audit each change),
# SI-10 (output validated).
class FedrampSignificantChangeService
  class Error < StandardError; end

  FIELDS = (%w[change_type emergency milestones impacted_controls] +
            FedrampSignificantChange::TEXT_FIELDS + FedrampSignificantChange::STRING_FIELDS +
            FedrampSignificantChange::DATE_FIELDS).freeze
  DOCUMENTATION = "documentation"
  HISTORY = 12.months # SCN-CSO-HIS

  Stage = Struct.new(:key, :rule_id, :label, :basis, :before, keyword_init: true)
  STAGES = {
    FedrampSignificantChange::TRANSFORMATIVE => [
      Stage.new(key: "initial_plans", rule_id: "SCN-TRF-NIP", label: "Initial plans", basis: :start, before: true),
      Stage.new(key: "final_plans", rule_id: "SCN-TRF-NFP", label: "Final plans", basis: :start, before: true),
      Stage.new(key: "after_finish", rule_id: "SCN-TRF-NAF", label: "After finishing", basis: :finish),
      Stage.new(key: "after_verification", rule_id: "SCN-TRF-NAV", label: "After verification", basis: :verification),
      Stage.new(key: DOCUMENTATION, rule_id: "SCN-TRF-UPD", label: "Updated service documentation published",
                basis: :finish)
    ],
    FedrampSignificantChange::ADAPTIVE => [
      Stage.new(key: "after_finish", rule_id: "SCN-ADP-NTF", label: "After finishing", basis: :finish)
    ]
  }.freeze

  # One notice a change needs: when it is due (nil until the date it counts
  # from is recorded) and the notice sent, if any.
  Deadline = Struct.new(:stage, :due_on, :timeframe, :notice, :retroactive, keyword_init: true) do
    def key = stage.key
    def rule_id = stage.rule_id
    def label = stage.label
    def sent_on = notice && Date.iso8601(notice["sent_on"])
    def notification? = stage.key != DOCUMENTATION

    # sent, late (sent after it was due), overdue, due, or waiting (for the
    # date it counts from).
    def status(today = Date.current)
      if notice
        due_on && sent_on > due_on ? "late" : "sent"
      elsif due_on.nil?
        "waiting"
      else
        today > due_on ? "overdue" : "due"
      end
    end
  end
  Result = Struct.new(:change, :created, :changes, keyword_init: true)

  def initialize(boundary)
    @boundary = boundary
  end

  def changes = @boundary.fedramp_significant_changes.newest_first

  def find!(uuid)
    @boundary.fedramp_significant_changes.find_by(uuid: uuid.to_s) ||
      raise(ActiveRecord::RecordNotFound, "No significant change #{uuid} on this boundary")
  end

  # Records a new change (change nil) or updates one; only the fields given
  # change.
  def record(attributes:, user:, change: nil)
    change ||= @boundary.fedramp_significant_changes.new(created_by: user)
    created = change.new_record?
    change.assign_attributes(attributes.to_h.stringify_keys.slice(*FIELDS))
    changed = change.changes.keys
    change.updated_by = user if changed.any?
    raise Error, change.errors.full_messages.to_sentence unless change.save

    Result.new(change: change, created: created, changes: changed)
  end

  def deadlines(change)
    STAGES.fetch(change.change_type, []).map do |stage|
      basis = basis_date(change, stage)
      timeframe = FedrampRules.timeframe(stage.rule_id)
      retroactive = change.emergency? && stage.before
      due = if retroactive
              change.finished_on && shift(change.finished_on, after_finish_timeframe(change))
      elsif basis
              shift(basis, timeframe, before: stage.before)
      end
      Deadline.new(stage: stage, due_on: due, timeframe: timeframe, notice: change.notice_for(stage.key),
                   retroactive: retroactive)
    end
  end

  # The Significant Change Notification, as of now.
  def notification(change)
    raise Error, "A routine recurring change needs no Significant Change Notification (SCN-RTR-NNR)" if change.routine?

    header = FedrampVulnerabilityReportService.new(@boundary).header(FedrampSignificantChange::DOCUMENT_TYPE)
    FedrampVulnerabilityReportService.validated!(FedrampSignificantChange::DOCUMENT_TYPE, header.merge(body(change)))
  end

  # Records that a notice was sent on a date, with the document as it stood
  # (updated service documentation has no document).
  def record_notice(change, stage:, sent_on:, user:)
    deadline = deadlines(change).find { |d| d.key == stage.to_s }
    raise Error, "#{change.change_type} changes have no #{stage.to_s.humanize.downcase} notice" unless deadline

    date = SparcNamespaceProps.iso_date(sent_on.to_s) && Date.iso8601(sent_on.to_s)
    raise Error, "The date sent must be a date in the form YYYY-MM-DD" unless date
    raise Error, "The date sent is in the future" if date > Date.current

    document = deadline.notification? ? notification(change) : nil
    notice = { "stage" => deadline.key, "rule_id" => deadline.rule_id, "sent_on" => date.iso8601,
               "recorded_at" => Time.current.utc.iso8601, "recorded_by_id" => user&.id,
               "recorded_by" => user&.display_label,
               "sha256" => document && Digest::SHA256.hexdigest(JSON.generate(document)), "document" => document }.compact
    change.update!(notices: Array(change.notices).reject { |n| n["stage"] == deadline.key } + [ notice ],
                   updated_by: user)
    notice
  end

  # The notifications FedRAMP requires the provider keep available
  # (SCN-CSO-HIS): every Adaptive or Transformative change recorded or
  # notified in the last 12 months.
  def history(now: Time.current)
    since = now - HISTORY
    changes.notifiable.select do |c|
      c.created_at >= since || Array(c.notices).any? { |n| n["sent_on"].to_s >= since.to_date.iso8601 }
    end
  end

  private

  def basis_date(change, stage)
    case stage.basis
    when :start then change.started_on || change.planned_start
    when :finish then change.finished_on
    when :verification then change.verified_on
    end
  end

  def after_finish_timeframe(change)
    stage = STAGES.fetch(change.change_type).find { |s| s.key == "after_finish" }
    FedrampRules.timeframe(stage.rule_id)
  end

  def shift(date, (type, num), before: false) = FedrampTimeframe.shift(date, type, num, before: before)

  # The schema's fields, then the information SCN-CSO-INF and SCN-ADP-NTF /
  # SCN-TRF-NAV require that the schema has no field for, as additional
  # information (SCN-CSO-ARI): the approver and the new risks.
  def body(change)
    plan = change.plan_summary && {
      "summary" => change.plan_summary, "plannedStart" => change.planned_start&.iso8601,
      "plannedCompletion" => change.planned_completion&.iso8601,
      "milestones" => Array(change.milestones).map do |m|
        { "milestoneDescription" => m["description"], "targetDate" => m["target_date"] }.compact
      end.presence
    }.compact
    {
      "assessorName" => change.assessor_name, "relatedVulnerability" => change.related_vulnerability,
      "changeType" => change.change_type, "changeTypeExplanation" => change.type_explanation,
      "changeDescription" => change.description, "reason" => change.reason,
      "customerImpact" => change.customer_impact, "planAndTimeline" => plan,
      "impactedControls" => Array(change.impacted_controls).presence, "impactAnalysis" => change.impact_analysis,
      "approverName" => change.approver_name, "approverTitle" => change.approver_title,
      "newRisksSummary" => change.new_risks
    }.compact
  end
end
