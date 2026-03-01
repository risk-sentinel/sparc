class CatalogControl < ApplicationRecord
  belongs_to :control_family

  validates :control_id, presence: true, uniqueness: { scope: :control_family_id }

  default_scope { order(:control_id) }

  def family_code
    control_family.code
  end
end
