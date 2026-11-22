# frozen_string_literal: true

# #1390 — a boundary's FedRAMP Ongoing Certification Report (CCM-OCR-AVL),
# every 3 months, covering the whole period since the previous one. Written
# from what SPARC records, validated against FedRAMP's pinned schema before
# it is returned:
#
#   certificationDataChanges        the FedRAMP rule and KSI answers changed in
#                                   the period, and the Adaptive and
#                                   Transformative changes finished in it,
#                                   plus any lines typed for the report
#   plannedCertificationDataChanges the Adaptive and Transformative changes
#                                   planned, or under way, through 3 months
#                                   after the period, plus any typed
#   acceptedVulnerabilities         a summary of the Accepted Vulnerability
#                                   Info (VER-RPT-AVI) for the period
#   transformativeChanges           Transformative changes started or finished
#                                   in the period
#   updatedRecommendations          typed for each report
#   activeAgencies                  the boundary's list of agencies using the
#                                   service
#   reportableIncidents             the FedRAMP Reportable Incidents active in
#                                   the period with their lessons learned; an
#                                   empty list attests that none occurred
#
# The period runs from the day after the last report issued (or 3 months
# back, for the first) to today. Issuing keeps the document as issued
# (FedrampOngoingReport); the next one is due 3 months after the period ends.
#
# NIST SP 800-53: CA-7 (continuous monitoring), PM-31, SI-10 (output
# validated).
class FedrampOngoingReportService
  class Error < StandardError; end

  DOCUMENT_TYPE = FedrampOngoingReport::DOCUMENT_TYPE
  CYCLE = 3.months # CCM-OCR-AVL
  ID_SAMPLE = 10
  MAX_LINES = 100

  # What a report is built from: its period and the lines typed for it.
  Input = Struct.new(:from, :to, :recommendations, :other_changes, :other_planned, keyword_init: true)

  def initialize(boundary)
    @boundary = boundary
  end

  def reports = @boundary.fedramp_ongoing_reports.newest_first
  def last_report = reports.first

  def find!(uuid)
    @boundary.fedramp_ongoing_reports.find_by(uuid: uuid.to_s) ||
      raise(ActiveRecord::RecordNotFound, "No Ongoing Certification Report #{uuid} on this boundary")
  end

  def default_period(today: Date.current)
    from = last_report ? last_report.period_to + 1 : today - CYCLE + 1
    [ [ from, today ].min, today ]
  end

  # When the next report is due (CCM-OCR-NRD): 3 months after the last
  # period ends, or nil before the first.
  def next_target_date = last_report && (last_report.period_to + CYCLE)

  # The input from request parameters; a blank period takes the default.
  def input(from: nil, to: nil, recommendations: nil, other_changes: nil, other_planned: nil)
    default_from, default_to = default_period
    period_from = date(from, :from) || default_from
    period_to = date(to, :to) || default_to
    raise Error, "The period ends (#{period_to}) before it starts (#{period_from})" if period_to < period_from
    raise Error, "The period ends in the future (#{period_to})" if period_to > Date.current

    Input.new(from: period_from, to: period_to, recommendations: lines(recommendations),
              other_changes: lines(other_changes), other_planned: lines(other_planned))
  end

  def build(input)
    header = FedrampVulnerabilityReportService.new(@boundary).header(DOCUMENT_TYPE)
    FedrampVulnerabilityReportService.validated!(DOCUMENT_TYPE, header.merge(body(input)))
  end

  # Issues the report: kept exactly as written. A period may not begin on
  # or before the end of one already issued.
  def issue(input, user:)
    if last_report && input.from <= last_report.period_to
      raise Error, "The period must start after the last report issued, which ended #{last_report.period_to}"
    end

    document = build(input)
    @boundary.fedramp_ongoing_reports.create!(
      period_from: input.from, period_to: input.to, recommendations: input.recommendations, document: document,
      sha256: Digest::SHA256.hexdigest(JSON.generate(document)), issued_by: user
    )
  end

  private

  def body(input)
    range = input.from.beginning_of_day.utc..input.to.end_of_day.utc
    {
      "reportPeriod" => { "from" => input.from.iso8601, "to" => input.to.iso8601 },
      "certificationDataChanges" => statement_changes(range) + finished_changes(input) + input.other_changes,
      "plannedCertificationDataChanges" => planned(input),
      "acceptedVulnerabilities" => accepted_vulnerabilities(input),
      "transformativeChanges" => transformative(input),
      "updatedRecommendations" => input.recommendations,
      "activeAgencies" => Array(@boundary.fedramp_active_agencies),
      "reportableIncidents" => { "incidents" => incidents(range) }
    }
  end

  def statement_changes(range)
    changed = @boundary.fedramp_statements.where(updated_at: range).order(:rule_id).group_by(&:kind)
    { FedrampRules::FRR => "FedRAMP rule", FedrampRules::KSI => "Key Security Indicator" }.filter_map do |kind, noun|
      ids = Array(changed[kind]).map(&:rule_id)
      next if ids.empty?

      more = ids.size > ID_SAMPLE ? ", and #{ids.size - ID_SAMPLE} more" : ""
      "#{ids.size} #{noun} #{ids.size == 1 ? 'answer' : 'answers'} updated: #{ids.first(ID_SAMPLE).join(', ')}#{more}"
    end
  end

  def notifiable = @boundary.fedramp_significant_changes.notifiable.order(:created_at)

  def finished_changes(input)
    notifiable.where(finished_on: input.from..input.to).map do |c|
      "#{c.change_type} change finished #{c.finished_on.iso8601}: #{c.description}"
    end
  end

  # Not finished by the end of the period, and started or planned to start
  # by the end of the planning horizon.
  def planned(input)
    horizon = input.to + CYCLE
    changes = notifiable.select do |c|
      next false if c.finished_on && c.finished_on <= input.to

      start = c.started_on || c.planned_start
      start.nil? || start <= horizon
    end
    lines = changes.map do |c|
      start = c.started_on ? "under way since #{c.started_on.iso8601}" : planned_when(c)
      "#{c.change_type} change #{start}: #{c.description}"
    end
    { "planningHorizonThrough" => horizon.iso8601, "changes" => lines + input.other_planned }
  end

  def planned_when(change) = change.planned_start ? "planned to start #{change.planned_start.iso8601}" : "planned (no start date)"

  def transformative(input)
    period = input.from..input.to
    notifiable.where(change_type: FedrampSignificantChange::TRANSFORMATIVE).select do |c|
      [ c.started_on, c.finished_on ].compact.any? { |d| period.cover?(d) }
    end.map do |c|
      dates = { "started" => c.started_on, "finished" => c.finished_on }.compact.map { |k, d| "#{k} #{d.iso8601}" }
      "#{c.description} (#{dates.join(', ')})"
    end
  end

  def accepted_vulnerabilities(input)
    avi = FedrampVulnerabilityReportService.accepted_vulnerability_info(@boundary, from: input.from.iso8601,
                                                                                   to: input.to.iso8601)
    count = Array(avi["acceptedVulnerabilities"]).size
    return "No accepted vulnerabilities in the period." if count.zero?

    "#{count} accepted #{count == 1 ? 'vulnerability' : 'vulnerabilities'} in the period; the full records are in " \
      "the Accepted Vulnerability Info (VER-RPT-AVI)."
  end

  # Reportable incidents that began on or before the period's end and were
  # not resolved before it began.
  def incidents(range)
    @boundary.fedramp_incidents.reportable.order(:created_at).filter_map do |i|
      occurred = i.started_at || i.detected_at || i.created_at
      next if occurred > range.end || (i.resolved_at && i.resolved_at < range.begin)

      { "summary" => i.description.presence || "Incident #{i.tracking_id}",
        "occurredAt" => occurred.utc.iso8601, "resolvedAt" => i.resolved_at&.utc&.iso8601,
        "incidentLessonsLearned" => Array(i.lessons_learned).presence }.compact
    end
  end

  def lines(value)
    list = value.is_a?(String) ? value.lines : Array(value)
    list = list.map { |v| v.to_s.strip }.compact_blank
    raise Error, "At most #{MAX_LINES} lines may be typed for each list" if list.size > MAX_LINES

    list
  end

  def date(value, name)
    text = value.to_s.strip
    return nil if text.empty?

    Date.iso8601(text)
  rescue Date::Error
    raise Error, "#{name} must be a date in the form YYYY-MM-DD (got #{text.inspect})"
  end
end
