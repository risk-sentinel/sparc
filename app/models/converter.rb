# frozen_string_literal: true

# Represents a framework converter — a lookup table that maps source
# framework identifiers (CCI, CIS Safeguard, OVAL test type, STIG SV/V-ID, etc.)
# to NIST SP 800-53 control IDs.
#
# Each converter has many entries (ConverterEntry) representing
# individual source→target mappings. Used by FrameworkMappingGeneratorService
# to auto-generate ControlMapping records from imported XCCDF/SCAP content.
#
# URLs use slug-based paths (e.g., /converters/disa-cci-to-nist-sp-800-53)
# instead of numeric IDs via to_param override.
class Converter < ApplicationRecord
  include Sluggable

  # Strips the numeric control suffix to derive the family (e.g. "AC-2(3)" → "AC").
  FAMILY_SUFFIX_PATTERN = /-\d+.*/

  has_many :converter_entries, dependent: :destroy

  before_validation :generate_uuid, on: :create

  validates :name, presence: true
  validates :uuid, presence: true, uniqueness: true
  validates :converter_type, presence: true, inclusion: { in: %w[cci_to_nist cis_to_nist scap_oval_to_nist stig_to_nist aws_config_to_nist aws_security_hub_to_nist custom] }
  validates :status, inclusion: { in: %w[draft complete deprecated processing failed] }

  scope :sorted, -> { order(updated_at: :desc) }
  scope :published, -> { where(status: "complete") }

  TYPES = %w[cci_to_nist cis_to_nist scap_oval_to_nist stig_to_nist aws_config_to_nist aws_security_hub_to_nist custom].freeze
  STATUSES = %w[draft complete deprecated processing failed].freeze

  TYPE_LABELS = {
    "cci_to_nist" => "CCI → NIST",
    "cis_to_nist" => "CIS → NIST",
    "scap_oval_to_nist" => "SCAP/OVAL → NIST",
    "stig_to_nist" => "STIG → NIST",
    "aws_config_to_nist" => "AWS Config → NIST",
    "aws_security_hub_to_nist" => "AWS Security Hub → NIST",
    "custom" => "Custom"
  }.freeze

  def type_label
    TYPE_LABELS[converter_type] || converter_type.titleize
  end

  # #499 slice 2 — which NIST 800-53 revision the converter's
  # `target_id` values are expressed in ("4" or "5"). Stored in
  # metadata_extra rather than a column to avoid a schema migration.
  # `ControlIdNormalizer.translate` consults this when a caller asks
  # for a different rev than the converter natively emits.
  def target_rev
    metadata_extra&.dig("target_rev")
  end

  def target_rev=(rev)
    self.metadata_extra = (metadata_extra || {}).merge("target_rev" => rev&.to_s)
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
      .map { |t| t.gsub(FAMILY_SUFFIX_PATTERN, "").upcase }
      .uniq
      .sort
  end

  def coverage_stats
    entries = converter_entries.to_a
    {
      total_entries: entries.size,
      unique_sources: entries.map(&:source_id).uniq.size,
      unique_targets: entries.map(&:target_id).uniq.size,
      families: entries.map { |e| e.target_id.gsub(FAMILY_SUFFIX_PATTERN, "").upcase }.uniq.sort,
      family_count: entries.map { |e| e.target_id.gsub(FAMILY_SUFFIX_PATTERN, "").upcase }.uniq.size
    }
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
