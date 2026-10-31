# frozen_string_literal: true

# 1.18.0-rf — documentation activity per boundary, week by week, for the
# Boundaries tab's sparklines (owner, 2026-10-29).
#
# Activity is the audit log (AuditEvent): every audited action on the boundary
# itself or on a document that belongs to it (SSP, SAP, SAR, POA&M, evidence,
# CDEF coverage run, and — #1301 — scan run and KSI validation). An event is tied to its boundary through its subject, so
# an event whose subject has since been hard-deleted no longer counts; a
# soft-deleted document's events still do.
#
# One grouped query for every boundary on the page and every week, however
# many there are. Callers pass only boundaries the viewer may see (the
# Boundaries tab lists AuthorizationBoundary.visible_to), and the result is a
# count of events, never their content.
#
# NIST SP 800-53 Rev 5:
#   AU-6 Audit Record Review — surfaces the audit trail's volume per system.
#   AC-3 Access Enforcement — only for boundaries the caller already lists.
class BoundaryActivity
  WEEKS = 26

  # How each audited subject type reaches its boundary. Literal SQL, never
  # built from input.
  VIA_SUBJECT = {
    "SspDocument"     => "INNER JOIN ssp_documents s ON s.id = audit_events.subject_id",
    "SapDocument"     => "INNER JOIN sap_documents s ON s.id = audit_events.subject_id",
    "SarDocument"     => "INNER JOIN sar_documents s ON s.id = audit_events.subject_id",
    "PoamDocument"    => "INNER JOIN poam_documents s ON s.id = audit_events.subject_id",
    "Evidence"        => "INNER JOIN evidences s ON s.id = audit_events.subject_id",
    "CdefCoverageRun" => "INNER JOIN cdef_coverage_runs s ON s.id = audit_events.subject_id",
    "ScanRun"         => "INNER JOIN scan_runs s ON s.id = audit_events.subject_id",
    "KsiValidation"   => "INNER JOIN ksi_validations s ON s.id = audit_events.subject_id"
  }.freeze

  # { boundary_id => [count per week, oldest first] }, WEEKS long, for every
  # id given (all zeros when nothing happened).
  def self.weekly(boundary_ids, weeks: WEEKS, now: Time.current)
    ids = Array(boundary_ids).map(&:to_i).uniq
    return {} if ids.empty?

    start = now.utc.beginning_of_week - (weeks - 1).weeks
    series = ids.index_with { Array.new(weeks, 0) }

    counts(ids, start).each do |(boundary_id, week), n|
      index = ((week_start(week) - start) / 1.week).round
      series[boundary_id.to_i][index] += n if index.between?(0, weeks - 1) && series.key?(boundary_id.to_i)
    end
    series
  end

  # #1301 — the boundary's most recent events, newest first, through the same
  # definition the weekly counts use. Each is an AuditEvent with its user.
  def self.latest(boundary_id, limit: 1)
    union = events([ boundary_id.to_i ], nil, columns: [ "audit_events.id" ])
    ids = AuditEvent.unscoped.from(Arel::Nodes::As.new(Arel::Nodes::Grouping.new(union), Arel.sql("events"))).select("events.id")
    AuditEvent.unscoped.where(id: ids).includes(:user).order(created_at: :desc, id: :desc).limit(limit).to_a
  end

  def self.counts(ids, start)
    AuditEvent.unscoped.from(Arel::Nodes::As.new(Arel::Nodes::Grouping.new(events(ids, start)), Arel.sql("events")))
      .group("events.ab_id").group(Arel.sql("date_trunc('week', events.created_at)")).count
  end
  private_class_method :counts

  # Every event on the boundaries or their documents, as one UNION ALL; since
  # `start` when given.
  def self.events(ids, start, columns: [ "audit_events.created_at" ])
    since = start ? { created_at: start.. } : {}
    direct = AuditEvent.unscoped
      .where(subject_type: "AuthorizationBoundary", subject_id: ids, **since)
      .select("audit_events.subject_id AS ab_id", *columns)
    via = VIA_SUBJECT.map do |type, join|
      AuditEvent.unscoped.joins(join)
        .where(subject_type: type, **since)
        .where("s.authorization_boundary_id IN (?)", ids)
        .select("s.authorization_boundary_id AS ab_id", *columns)
    end
    [ direct, *via ].map(&:arel).reduce { |all, one| Arel::Nodes::UnionAll.new(all, one) }
  end
  private_class_method :events

  def self.week_start(value)
    (value.is_a?(String) ? Time.zone.parse(value) : value).to_time.utc
  end
  private_class_method :week_start
end
