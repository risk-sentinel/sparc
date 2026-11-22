# frozen_string_literal: true

# #1390 — one change a FedRAMP provider evaluated (SCN-CSO-EVA), kept as the
# auditable record of that evaluation (SCN-CSO-MAR):
#
#   change_type          Routine (a routine recurring change: recorded, never
#                        notified, SCN-RTR-NNR), Adaptive or Transformative
#   description ...      what a Significant Change Notification carries
#                        (SCN-CSO-INF): categorization, reason, customer impact,
#                        plan and timeline with milestones, impacted KSIs or
#                        controls, impact analysis, assessor, related
#                        vulnerability, and the approver's name and title
#   new_risks            new risks or vulnerabilities from the change
#                        (SCN-ADP-NTF, SCN-TRF-NAV)
#   emergency            made during an emergency or incident, notified
#                        afterwards (SCN-CSO-EMG)
#   started_on, finished_on, verified_on
#                        when it started, finished, and its verification,
#                        assessment or validation completed; the notice
#                        deadlines count from these (FedrampSignificantChangeService)
#   notices              each notice sent: its stage, the date sent, who
#                        recorded it, and the document sent (SCN-CSO-HIS)
#
# A change is never deleted.
#
# NIST SP 800-53: CM-3 (configuration change control), CM-4 (impact
# analyses), CA-7 (continuous monitoring), SI-10.
class FedrampSignificantChange < ApplicationRecord
  DOCUMENT_TYPE = "significant-change-notifications"
  ROUTINE = "Routine"
  ADAPTIVE = "Adaptive"
  TRANSFORMATIVE = "Transformative"
  TEXT_FIELDS = %w[description type_explanation reason customer_impact plan_summary impact_analysis new_risks].freeze
  STRING_FIELDS = %w[assessor_name related_vulnerability approver_name approver_title].freeze
  DATE_FIELDS = %w[planned_start planned_completion started_on finished_on verified_on].freeze
  MILESTONE_KEYS = %w[description target_date].freeze
  MAX_TEXT = 20_000
  MAX_STRING = 500
  MAX_ITEMS = 50

  belongs_to :authorization_boundary
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  validates :change_type, inclusion: { in: ->(_) { change_types } }
  validates :description, presence: true
  TEXT_FIELDS.each { |f| validates f, length: { maximum: MAX_TEXT } }
  STRING_FIELDS.each { |f| validates f, length: { maximum: MAX_STRING } }
  validate :milestones_are_valid
  validate :impacted_controls_are_valid
  validate :plan_has_summary
  validate :dates_in_order

  scope :notifiable, -> { where.not(change_type: ROUTINE) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # Routine, then the schema's types (Adaptive, Transformative).
  def self.change_types = [ ROUTINE, *notifiable_types ]

  def self.notifiable_types
    @notifiable_types ||= Array(FedrampPackageSchemas.fetch(DOCUMENT_TYPE).document.dig("properties", "changeType", "enum")).freeze
  end

  def routine? = change_type == ROUTINE
  def transformative? = change_type == TRANSFORMATIVE
  def to_param = uuid

  (TEXT_FIELDS + STRING_FIELDS).each do |field|
    define_method("#{field}=") { |v| super(v.to_s.strip.presence) }
  end

  def change_type=(value)
    super(value.to_s.strip.presence)
  end

  # Accepts an array of hashes, or the index-keyed hash a form posts; drops
  # empty rows.
  def milestones=(rows)
    super(FormRows.normalize(rows, MILESTONE_KEYS))
  end

  # A list, or text with one identifier per line or comma.
  def impacted_controls=(value)
    list = value.is_a?(String) ? value.split(/[\n,]/) : Array(value)
    super(list.map { |c| c.to_s.strip }.compact_blank.uniq)
  end

  def notice_for(stage) = Array(notices).find { |n| n["stage"] == stage }

  private

  def milestones_are_valid
    list = Array(milestones)
    errors.add(:milestones, "may list at most #{MAX_ITEMS}") if list.size > MAX_ITEMS
    list.each_with_index do |m, i|
      errors.add(:milestones, "#{i + 1}: a description is required") if m["description"].blank?
      if m["target_date"].present? && !SparcNamespaceProps.iso_date(m["target_date"])
        errors.add(:milestones, "#{i + 1}: target date must be a date in the form YYYY-MM-DD")
      end
    end
  end

  def impacted_controls_are_valid
    errors.add(:impacted_controls, "may list at most #{MAX_ITEMS * 4}") if Array(impacted_controls).size > MAX_ITEMS * 4
  end

  # The notification's plan and timeline needs its summary (planAndTimeline.summary).
  def plan_has_summary
    return if plan_summary.present?
    return unless planned_start || planned_completion || Array(milestones).any?

    errors.add(:plan_summary, "is required when the plan has dates or milestones")
  end

  def dates_in_order
    if planned_start && planned_completion && planned_completion < planned_start
      errors.add(:planned_completion, "is before the planned start")
    end
    errors.add(:finished_on, "is before the start") if started_on && finished_on && finished_on < started_on
    errors.add(:verified_on, "is before the finish") if finished_on && verified_on && verified_on < finished_on
    errors.add(:verified_on, "needs the finish date") if verified_on && finished_on.nil?
  end
end
