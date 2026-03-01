class ControlFamily < ApplicationRecord
  belongs_to :control_catalog
  has_many :catalog_controls, dependent: :destroy

  validates :code, presence: true, uniqueness: { scope: :control_catalog_id }
  validates :name, presence: true

  default_scope { order(:sort_order, :code) }
end
