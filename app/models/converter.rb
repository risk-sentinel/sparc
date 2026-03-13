# frozen_string_literal: true

# Represents a framework converter — a lookup table that maps source
# framework identifiers (CCI, CIS Safeguard, OVAL test type, etc.)
# to NIST SP 800-53 control IDs.
#
# Each converter has many entries (ConverterEntry) representing
# individual source→target mappings. Used by FrameworkMappingGeneratorService
# to auto-generate ControlMapping records from imported XCCDF/SCAP content.
class Converter < ApplicationRecord
  has_many :converter_entries, dependent: :destroy

  before_validation :generate_uuid, on: :create

  validates :name, presence: true
  validates :uuid, presence: true, uniqueness: true
  validates :converter_type, presence: true, inclusion: { in: %w[cci_to_nist cis_to_nist scap_oval_to_nist custom] }
  validates :status, inclusion: { in: %w[draft complete deprecated] }

  scope :sorted, -> { order(updated_at: :desc) }
  scope :published, -> { where(status: "complete") }

  TYPES = %w[cci_to_nist cis_to_nist scap_oval_to_nist custom].freeze
  STATUSES = %w[draft complete deprecated].freeze

  TYPE_LABELS = {
    "cci_to_nist" => "CCI → NIST",
    "cis_to_nist" => "CIS → NIST",
    "scap_oval_to_nist" => "SCAP/OVAL → NIST",
    "custom" => "Custom"
  }.freeze

  def type_label
    TYPE_LABELS[converter_type] || converter_type.titleize
  end

  def entries_count
    converter_entries.count
  end

  def unique_source_ids
    converter_entries.distinct.count(:source_id)
  end

  def unique_target_ids
    converter_entries.distinct.count(:target_id)
  end

  def target_families
    converter_entries
      .pluck(:target_id)
      .map { |t| t.gsub(/-\d+.*/, "").upcase }
      .uniq
      .sort
  end

  def coverage_stats
    entries = converter_entries.to_a
    {
      total_entries: entries.size,
      unique_sources: entries.map(&:source_id).uniq.size,
      unique_targets: entries.map(&:target_id).uniq.size,
      families: entries.map { |e| e.target_id.gsub(/-\d+.*/, "").upcase }.uniq.sort,
      family_count: entries.map { |e| e.target_id.gsub(/-\d+.*/, "").upcase }.uniq.size
    }
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
