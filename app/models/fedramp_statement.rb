# frozen_string_literal: true

# #1390 — a boundary's answer to one FedRAMP rule (FRR) or Key Security
# Indicator (KSI), as its Security Decision Record carries it:
#
#   status          Implemented / Partially Implemented / Not Implemented
#                   (the SDR schema's values)
#   implementation  how the rule is followed or the KSI demonstrated, or why
#                   not and the resulting risk (SDR-CSO-FRR, SDR-CSX-KSI)
#   validation      that it is in place and working as intended
#   assessment      the verification of it
#   tests           (KSI) the tests that demonstrate it
#   evidence        (KSI) evidence entries: type, description, location,
#                   text, last updated
#
# Allowed values are read from the vendored SDR schema. Each change counts
# up the boundary's SDR version (metadata.version).
#
# NIST SP 800-53: PL-2 (security documentation), CA-2 (control assessments),
# SI-10 (information input validation).
class FedrampStatement < ApplicationRecord
  DOCUMENT_TYPE = "security-decision-record"
  TEXT_FIELDS = %w[implementation validation assessment].freeze
  EVIDENCE_KEYS = %w[evidence_type description location text last_updated].freeze
  MAX_TEXT = 20_000
  MAX_ITEMS = 50
  URL_FORMAT = FedrampPackageOverview::URL_FORMAT

  belongs_to :authorization_boundary
  belongs_to :updated_by, class_name: "User", optional: true

  validates :kind, inclusion: { in: FedrampRules::KINDS }
  validates :rule_id, presence: true, format: { with: /\A[A-Z]{3}(-[A-Z]{2,4}){1,2}\z/ }
  validates :rule_id, uniqueness: { scope: %i[authorization_boundary_id kind] }
  validates :status, inclusion: { in: ->(_) { statuses } }, allow_nil: true
  TEXT_FIELDS.each { |f| validates f, length: { maximum: MAX_TEXT } }
  validate :tests_are_strings
  validate :evidence_is_valid

  after_commit :count_sdr_version

  scope :frr, -> { where(kind: FedrampRules::FRR) }
  scope :ksi, -> { where(kind: FedrampRules::KSI) }

  class << self
    def statuses = enum_at("properties", "fedRampRequirements", "items", "properties", "frrImplementationStatus")
    def evidence_types = enum_at("$defs", "evidence", "properties", "evidenceType")

    private

    def enum_at(*path)
      @enums ||= {}
      @enums[path] ||= Array(FedrampPackageSchemas.fetch(DOCUMENT_TYPE).document.dig(*path)&.fetch("enum", nil)).freeze
    end
  end

  def tests=(list)
    super(Array(list).map { |t| t.to_s.strip }.compact_blank)
  end

  # Accepts an array of hashes, or the index-keyed hash a form posts; drops
  # empty rows.
  def evidence=(rows)
    super(FormRows.normalize(rows, EVIDENCE_KEYS))
  end

  def status=(value)
    super(value.to_s.strip.presence)
  end

  TEXT_FIELDS.each do |field|
    define_method("#{field}=") { |v| super(v.to_s.strip.presence) }
  end

  def blank_statement? = status.nil? && TEXT_FIELDS.all? { |f| self[f].blank? }

  private

  def tests_are_strings
    errors.add(:tests, "may list at most #{MAX_ITEMS}") if Array(tests).size > MAX_ITEMS
  end

  def evidence_is_valid
    list = Array(evidence)
    errors.add(:evidence, "may list at most #{MAX_ITEMS}") if list.size > MAX_ITEMS
    list.each_with_index do |e, i|
      row = "entry #{i + 1}"
      if e["evidence_type"].present? && !self.class.evidence_types.include?(e["evidence_type"])
        errors.add(:evidence, "#{row}: type must be one of #{self.class.evidence_types.join(', ')}")
      end
      errors.add(:evidence, "#{row}: location must be an http(s) address") if e["location"].present? && !e["location"].match?(URL_FORMAT)
      if e["last_updated"].present? && !SparcNamespaceProps.iso_date(e["last_updated"])
        errors.add(:evidence, "#{row}: last updated must be a date in the form YYYY-MM-DD")
      end
    end
  end

  def count_sdr_version
    return unless destroyed? || saved_changes.except("updated_at", "updated_by_id").any?

    AuthorizationBoundary.where(id: authorization_boundary_id).update_all("fedramp_sdr_version = fedramp_sdr_version + 1")
  end
end
