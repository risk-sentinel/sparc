# frozen_string_literal: true

# Represents an OSCAL Control Mapping Collection — a cross-walk between
# two control catalogs (e.g., NIST SP 800-53 Rev 5 ↔ ISO 27001).
#
# Each mapping has many entries (ControlMappingEntry) that define individual
# source-to-target control relationships with relationship types aligned
# to NIST IR 8477 set-theory mapping.
#
# Exports to OSCAL v1.2.1 mapping-collection JSON via OscalMappingExportService.
class ControlMapping < ApplicationRecord
  include OscalMetadata

  belongs_to :source_catalog, class_name: "ControlCatalog"
  belongs_to :target_catalog, class_name: "ControlCatalog"
  has_many   :control_mapping_entries, dependent: :destroy

  before_validation :generate_uuid, on: :create

  validates :name, presence: true
  validates :uuid, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[draft complete not-complete deprecated superseded] }
  validates :method_type, inclusion: { in: %w[human automation hybrid] }
  validates :matching_rationale, inclusion: { in: %w[syntactic semantic functional] }

  scope :sorted, -> { order(updated_at: :desc) }
  scope :published, -> { where(status: "complete") }

  STATUSES  = %w[draft complete not-complete deprecated superseded].freeze
  METHODS   = %w[human automation hybrid].freeze
  RATIONALES = %w[syntactic semantic functional].freeze

  def published?
    status == "complete"
  end

  def entries_count
    control_mapping_entries.count
  end

  def oscal_document_version
    mapping_version
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
