# Represents a component on the leveraged side that the leveraging
# system inherits (NIST OSCAL Implementation Layers deck, slide 20).
# Each LeveragedAuthorization gets at least one component of type
# `this-system` representing the leveraged system itself, plus one
# per shared capability the leveraging system relies on.
class LeveragedAuthorizationComponent < ApplicationRecord
  belongs_to :leveraged_authorization

  COMPONENT_TYPES = %w[
    this-system software hardware service policy
    process-procedure plan guidance standard validation
  ].freeze

  before_validation :assign_uuid_if_blank

  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }
  validates :title, presence: true
  validates :component_type, inclusion: { in: COMPONENT_TYPES }

  private

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end
end
