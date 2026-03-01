class ControlCatalog < ApplicationRecord
  has_many :control_families, dependent: :destroy
  has_many :catalog_controls, through: :control_families

  validates :name, presence: true, uniqueness: true

  def total_controls
    catalog_controls.count
  end
end
