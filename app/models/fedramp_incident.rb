# frozen_string_literal: true

# #1390 — one incident a FedRAMP provider evaluated (IEC-CSO-EFR), with what
# its Initial, Ongoing and Final Incident Reports carry (IEC-CSO-IIR, -OIR,
# -FIR):
#
#   tracking_id          the provider's own identifier, the same on every report
#   reportable           a FedRAMP Reportable Incident: it affects, or is likely
#                        to affect, the confidentiality or integrity of federal
#                        customer data. Only a reportable incident is reported
#   coordinator ...      the federal incident response coordinator, description,
#                        timeline (start, detection and its source, evaluation
#                        completed, milestones), functional impact, recovery
#                        plan, likely affected agencies, observed activity,
#                        indicators of compromise, related CVEs, root cause,
#                        response and recovery activities, resolution
#   ratings              every Potential Agency Impact N-rating given (IEC-CSO-EFI),
#                        oldest first; the last is the current one. Until one is
#                        given, a reportable incident is treated as N5 (IEC-CSO-DPR)
#   lessons_learned      lessons learned and changes made as a result, for the
#                        Ongoing Certification Report (CCM-OCR-AVL)
#   reports              each report sent: its type, when, who recorded it, and
#                        the document sent
#
# An incident is never deleted. Reading or changing one needs incident.read /
# incident.write on the boundary.
#
# NIST SP 800-53: IR-4 (incident handling), IR-5 (incident monitoring), IR-6
# (incident reporting), IR-8, SI-10.
class FedrampIncident < ApplicationRecord
  DOCUMENT_TYPE = "incident-report"
  TEXT_FIELDS = %w[description evaluation_notes functional_impact recovery_plan observed_activity
                   root_cause response_activities].freeze
  STRING_FIELDS = %w[tracking_id coordinator detection_source].freeze
  TIME_FIELDS = %w[started_at detected_at evaluation_completed_at resolved_at].freeze
  LIST_FIELDS = %w[affected_agencies indicators related_cve_ids lessons_learned].freeze
  MILESTONE_KEYS = %w[occurred_at description].freeze
  CVE_FORMAT = /\ACVE-\d{4}-\d{4,}\z/
  ASSUMED_RATING = 5
  MAX_TEXT = 20_000
  MAX_STRING = 500
  MAX_ITEMS = 200

  belongs_to :authorization_boundary
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  validates :tracking_id, presence: true, uniqueness: { scope: :authorization_boundary_id }
  TEXT_FIELDS.each { |f| validates f, length: { maximum: MAX_TEXT } }
  STRING_FIELDS.each { |f| validates f, length: { maximum: MAX_STRING } }
  validate :lists_are_valid
  validate :milestones_are_valid
  validate :ratings_are_valid
  validate :times_in_order

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :reportable, -> { where(reportable: true) }
  scope :unresolved, -> { where(resolved_at: nil) }

  def self.report_types
    @report_types ||= Array(FedrampPackageSchemas.fetch(DOCUMENT_TYPE).document.dig("properties", "reportType", "enum")).freeze
  end

  def self.n_ratings
    @n_ratings ||= Array(FedrampPackageSchemas.fetch(FedrampPackageSchemas::COMMON).document.dig("$defs", "nRating", "enum")).freeze
  end

  def to_param = uuid
  def resolved? = resolved_at.present?

  (TEXT_FIELDS + STRING_FIELDS).each do |field|
    define_method("#{field}=") { |v| super(v.to_s.strip.presence) }
  end

  # A list, or text with one entry per line.
  LIST_FIELDS.each do |field|
    define_method("#{field}=") do |value|
      list = value.is_a?(String) ? value.lines : Array(value)
      super(list.map { |v| v.to_s.strip }.compact_blank.uniq)
    end
  end

  def related_cve_ids=(value)
    list = value.is_a?(String) ? value.split(/[\s,]+/) : Array(value)
    super(list.map { |v| v.to_s.strip.upcase }.compact_blank.uniq)
  end

  # Each milestone's time is kept as UTC ISO 8601 (a form posts local time
  # without a zone, read in the application's time zone).
  def milestones=(rows)
    super(FormRows.normalize(rows, MILESTONE_KEYS).map do |m|
      time = m["occurred_at"] && parse_time(m["occurred_at"])
      time ? m.merge("occurred_at" => time.utc.iso8601) : m
    end)
  end

  # The current N-rating, or nil before one is given.
  def current_rating = Array(ratings).last&.fetch("rating", nil)

  # Gives the incident a new N-rating (kept in its history), unless it is
  # the current one already. Blank leaves it as it is.
  def current_rating=(value)
    return if value.to_s.strip.empty?

    rating = Integer(value.to_s, exception: false)
    @invalid_rating = value.to_s unless self.class.n_ratings.include?(rating)
    return if @invalid_rating || rating == current_rating

    self.ratings = Array(ratings) + [ { "rating" => rating, "rated_at" => Time.current.utc.iso8601 } ]
  end

  # The N-rating its deadlines follow: the current one, or N5 until one is
  # given (IEC-CSO-DPR).
  def effective_rating = current_rating || ASSUMED_RATING

  def reports_of(type) = Array(reports).select { |r| r["report_type"] == type }
  def last_report = Array(reports).max_by { |r| r["sent_at"].to_s }

  private

  def lists_are_valid
    LIST_FIELDS.each do |field|
      errors.add(field, "may list at most #{MAX_ITEMS}") if Array(self[field]).size > MAX_ITEMS
    end
    bad = Array(related_cve_ids).grep_v(CVE_FORMAT)
    errors.add(:related_cve_ids, "must be CVE identifiers (CVE-YYYY-NNNN): #{bad.join(', ')}") if bad.any?
  end

  def milestones_are_valid
    Array(milestones).each_with_index do |m, i|
      errors.add(:milestones, "#{i + 1}: a description is required") if m["description"].blank?
      errors.add(:milestones, "#{i + 1}: when it occurred is required") if m["occurred_at"].blank?
      if m["occurred_at"].present? && !iso_time?(m["occurred_at"])
        errors.add(:milestones, "#{i + 1}: when it occurred must be a date and time")
      end
    end
  end

  def ratings_are_valid
    errors.add(:current_rating, "must be one of #{self.class.n_ratings.join(', ')}") if @invalid_rating
    Array(ratings).each do |r|
      errors.add(:ratings, "must each be one of #{self.class.n_ratings.join(', ')}") unless self.class.n_ratings.include?(r["rating"])
    end
  end

  def times_in_order
    errors.add(:detected_at, "is before the start") if started_at && detected_at && detected_at < started_at
    if detected_at && evaluation_completed_at && evaluation_completed_at < detected_at
      errors.add(:evaluation_completed_at, "is before the detection")
    end
    errors.add(:resolved_at, "is before the start") if started_at && resolved_at && resolved_at < started_at
  end

  def iso_time?(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    false
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
