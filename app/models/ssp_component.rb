class SspComponent < ApplicationRecord
  belongs_to :ssp_document
  belongs_to :cdef_document, optional: true
  has_many :ssp_by_components, dependent: :delete_all

  validates :uuid, presence: true
  validates :component_type, presence: true
  validates :title, presence: true
  validates :description, presence: true

  COMPONENT_TYPES = %w[
    this-system software hardware service policy
    process-procedure plan guidance standard validation
  ].freeze

  STATUS_STATES = %w[operational under-development disposition other].freeze

  scope :this_system, -> { where(component_type: "this-system") }
end
