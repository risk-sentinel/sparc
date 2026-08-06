# frozen_string_literal: true

# Represents a single mapping entry (map) within an OSCAL Control Mapping
# Collection — a relationship between a source control/statement and a
# target control/statement.
#
# Relationship types are aligned with NIST IR 8477 set-theory mapping:
#   equal, equivalent, subset, superset, intersects
class ControlMappingEntry < ApplicationRecord
  include ControlIdentifiable
  # #911 — TARGET only. `source_control_id` is by definition the non-NIST side
  # of the mapping: a FedRAMP KSI entry stores `ksi-iam-01` here and the NIST
  # control in `target_control_id`. `ControlId.canonical` encodes NIST numbering,
  # so it strips KSI's zero-padding to `ksi-iam-1` — an identifier the KSI
  # catalog does not contain, which silently emptied the mappings endpoint.
  #
  # The source identifier persists exactly as it arrived; the NIST side is the
  # one that has to line up with a catalog. Promoting that split into
  # first-class columns across the control-bearing models is #912.
  canonicalises_control_id :target_control_id

  belongs_to :control_mapping, touch: true

  before_validation :generate_uuid, on: :create

  validates :uuid, presence: true, uniqueness: true
  validates :source_control_id, presence: true
  validates :target_control_id, presence: true
  validates :relationship, presence: true,
            inclusion: { in: %w[equal equivalent subset superset intersects] }
  validates :source_type, inclusion: { in: %w[control statement] }
  validates :target_type, inclusion: { in: %w[control statement] }
  validates :source_control_id, uniqueness: {
    scope: [ :control_mapping_id, :target_control_id ],
    message: "to target pair already exists in this mapping"
  }

  default_scope { order(:row_order) }

  RELATIONSHIPS  = %w[equal equivalent subset superset intersects].freeze
  SUBJECT_TYPES  = %w[control statement].freeze

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
