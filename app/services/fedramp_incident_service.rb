# frozen_string_literal: true

# #1390 — a boundary's FedRAMP incidents (FedrampIncident): recording each one
# evaluated, when each report is due, and the Incident Report itself (Initial,
# Ongoing or Final; IEC-CSO-IIR / -OIR / -FIR), validated against FedRAMP's
# pinned schema before it is returned. The boundary's FedRAMP page and
# Api::V1::FedrampIncidentsController are thin clients of it.
#
# When each report is due depends on the boundary's certification class and
# the incident's Potential Agency Impact N-rating, as FedRAMP's rules file
# sets it (pain_timeframes), and so does whether it is a MUST or a SHOULD
# (Class A SHOULD give initial and ongoing reports). Until the incident is
# rated it is treated as N5 (IEC-CSO-DPR).
#
#   Initial  from the completed FedRAMP Reportable Incident evaluation
#   Ongoing  from the last report sent, until the incident is resolved
#   Final    from the resolution
#
# Only a FedRAMP Reportable Incident is reported. A Final report needs the
# resolution time.
#
# NIST SP 800-53: IR-4, IR-5, IR-6, AU-12 (the controllers audit each change),
# SI-10 (output validated).
class FedrampIncidentService
  class Error < StandardError; end

  FIELDS = (%w[reportable milestones current_rating] + FedrampIncident::TEXT_FIELDS + FedrampIncident::STRING_FIELDS +
            FedrampIncident::TIME_FIELDS + FedrampIncident::LIST_FIELDS + %w[related_cve_ids]).uniq.freeze
  RULES = { "Initial" => "IEC-CSO-IIR", "Ongoing" => "IEC-CSO-OIR", "Final" => "IEC-CSO-FIR" }.freeze
  CLOCK_SKEW = 5.minutes

  # One report an incident needs: when it is due (nil until the time it
  # counts from is recorded), FedRAMP's force for the class, and the last
  # report of the type sent.
  Deadline = Struct.new(:report_type, :rule_id, :due_at, :timeframe, :force, :report, :status, keyword_init: true)
  Result = Struct.new(:incident, :created, :changes, keyword_init: true)

  def initialize(boundary)
    @boundary = boundary
  end

  def incidents = @boundary.fedramp_incidents.newest_first

  def find!(uuid)
    @boundary.fedramp_incidents.find_by(uuid: uuid.to_s) ||
      raise(ActiveRecord::RecordNotFound, "No incident #{uuid} on this boundary")
  end

  def record(attributes:, user:, incident: nil)
    incident ||= @boundary.fedramp_incidents.new(created_by: user)
    created = incident.new_record?
    attrs = attributes.to_h.stringify_keys.slice(*FIELDS)
    rating = attrs.delete("current_rating")
    incident.assign_attributes(attrs)
    incident.current_rating = rating unless rating.nil?
    changed = incident.changes.keys
    incident.updated_by = user if changed.any?
    raise Error, incident.errors.full_messages.to_sentence unless incident.save

    Result.new(incident: incident, created: created, changes: changed)
  end

  # Why the incident has no report deadlines, or nil when it has them.
  def no_deadlines_reason(incident)
    return "Not a FedRAMP Reportable Incident, so it is not reported." unless incident.reportable?
    return "Set the boundary's FedRAMP certification class; the report deadlines depend on it." if klass.blank?

    nil
  end

  def deadlines(incident, now: Time.current)
    return [] if no_deadlines_reason(incident)

    RULES.map do |type, rule_id|
      frame = FedrampRules.incident_timeframe(rule_id, klass, incident.effective_rating)
      basis = basis_time(incident, type)
      due = frame && basis && FedrampTimeframe.shift(basis, frame[0], frame[1])
      Deadline.new(report_type: type, rule_id: rule_id, due_at: due, timeframe: frame&.first(2), force: frame&.last,
                   report: incident.reports_of(type).max_by { |r| r["sent_at"].to_s },
                   status: status(incident, type, due, frame, now))
    end
  end

  # The incident report of a type, as of now.
  def report(incident, type)
    type = type.to_s
    unless FedrampIncident.report_types.include?(type)
      raise Error, "report type must be one of: #{FedrampIncident.report_types.join(', ')}"
    end
    raise Error, "#{incident.tracking_id} is not a FedRAMP Reportable Incident, so it is not reported" unless incident.reportable?
    raise Error, "A Final report needs the time the incident was resolved" if type == "Final" && !incident.resolved?

    header = FedrampVulnerabilityReportService.new(@boundary).header(FedrampIncident::DOCUMENT_TYPE)
    FedrampVulnerabilityReportService.validated!(FedrampIncident::DOCUMENT_TYPE, header.merge(body(incident, type)))
  end

  # Records that a report was sent at a time, with the document as it stood.
  def record_report(incident, type:, sent_at:, user:)
    time = parse_time(sent_at)
    raise Error, "The time sent must be a date and time" unless time
    raise Error, "The time sent is in the future" if time > Time.current + CLOCK_SKEW

    document = report(incident, type)
    entry = { "report_type" => type.to_s, "rule_id" => RULES[type.to_s], "sent_at" => time.utc.iso8601,
              "recorded_at" => Time.current.utc.iso8601, "recorded_by_id" => user&.id,
              "recorded_by" => user&.display_label,
              "sha256" => Digest::SHA256.hexdigest(JSON.generate(document)), "document" => document }.compact
    incident.update!(reports: Array(incident.reports) + [ entry ], updated_by: user)
    entry
  end

  private

  def klass = @boundary.fedramp_profile.last

  def basis_time(incident, type)
    case type
    when "Initial" then incident.evaluation_completed_at
    when "Ongoing" then ongoing_basis(incident)
    when "Final" then incident.resolved_at
    else nil # not a report type: no deadline basis
    end
  end

  # Ongoing reports follow the last report sent, once an Initial report has
  # been, until the incident is resolved.
  def ongoing_basis(incident)
    return nil if incident.resolved? || incident.reports_of("Initial").empty?

    Time.iso8601(incident.last_report["sent_at"])
  end

  # sent, late, overdue, due, waiting, not_needed (an Ongoing report once
  # resolved), untimed (no timeframe for N0).
  def status(incident, type, due, frame, now)
    return "untimed" unless frame
    return ongoing_status(incident, due, now) if type == "Ongoing"

    sent = incident.reports_of(type).map { |r| Time.iso8601(r["sent_at"]) }.min
    return sent_status(sent, due) if sent
    return "waiting" unless due

    due_status(due, now)
  end

  def ongoing_status(incident, due, now)
    return "not_needed" if incident.resolved?
    return "waiting" unless due

    due_status(due, now)
  end

  def sent_status(sent, due) = due && sent > due ? "late" : "sent"

  def due_status(due, now) = now > due ? "overdue" : "due"

  def parse_time(value)
    value.respond_to?(:utc) ? value : Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def body(incident, type)
    iso = ->(t) { t&.utc&.iso8601 }
    timeline = {
      "startedAt" => iso.(incident.started_at), "detectedAt" => iso.(incident.detected_at),
      "detectionSource" => incident.detection_source, "evaluationCompletedAt" => iso.(incident.evaluation_completed_at),
      "milestones" => Array(incident.milestones).map do |m|
        { "occurredAt" => m["occurred_at"], "milestoneDescription" => m["description"] }
      end.presence
    }.compact
    ratings = Array(incident.ratings).map { |r| r["rating"] }
    impact = { "historicalRating" => ratings[0...-1].presence, "currentRating" => ratings.last,
               "evaluationNotes" => incident.evaluation_notes }.compact
    {
      "reportType" => type, "providerTrackingId" => incident.tracking_id,
      "federalIncidentCoordinator" => incident.coordinator, "incidentDescription" => incident.description,
      "timeline" => timeline.presence, "potentialImpact" => impact.presence,
      "functionalImpact" => incident.functional_impact, "recoveryPlan" => incident.recovery_plan,
      "affectedAgencies" => Array(incident.affected_agencies).presence,
      "observedActivity" => incident.observed_activity,
      "indicatorsOfCompromise" => Array(incident.indicators).presence,
      "relatedCveIds" => Array(incident.related_cve_ids).presence, "rootCause" => incident.root_cause,
      "responseAndRecoveryActivities" => incident.response_activities, "resolvedAt" => iso.(incident.resolved_at)
    }.compact
  end
end
