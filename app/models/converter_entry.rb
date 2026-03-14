# frozen_string_literal: true

# Represents a single source→target mapping entry within a Converter.
# For example: CCI-000015 → ac-2, or "1.1.1" → cm-6.
#
# Relationship types follow NIST IR 8477 set-theory:
#   equal, equivalent, subset, superset, intersects
class ConverterEntry < ApplicationRecord
  belongs_to :converter, touch: true

  before_validation :generate_uuid, on: :create

  validates :uuid, presence: true, uniqueness: true
  validates :source_id, presence: true
  validates :target_id, presence: true
  validates :relationship, presence: true,
            inclusion: { in: %w[equal equivalent subset superset intersects] }
  validates :source_id, uniqueness: {
    scope: [ :converter_id, :target_id ],
    message: "to target pair already exists in this converter"
  }

  default_scope { order(:row_order) }

  RELATIONSHIPS = %w[equal equivalent subset superset intersects].freeze

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
