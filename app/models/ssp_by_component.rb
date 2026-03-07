class SspByComponent < ApplicationRecord
  belongs_to :ssp_control
  belongs_to :ssp_component

  validates :uuid, presence: true

  IMPLEMENTATION_STATUSES = %w[
    implemented partial planned alternative not-applicable
  ].freeze
end
