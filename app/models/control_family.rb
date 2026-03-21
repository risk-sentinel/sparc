class ControlFamily < ApplicationRecord
  belongs_to :control_catalog
  has_many :catalog_controls, dependent: :destroy

  validates :code, presence: true, uniqueness: { scope: :control_catalog_id },
                   format: { with: /\A[A-Z][A-Z0-9\-]{0,9}\z/, message: "must start with an uppercase letter, 1-10 characters (letters, digits, hyphens)" }
  validates :name, presence: true

  before_validation :normalize_code
  before_validation :set_default_sort_order, on: :create

  default_scope { order(:sort_order, :code) }

  def total_controls
    catalog_controls.count
  end

  private

  def normalize_code
    self.code = code.to_s.strip.upcase if code.present?
  end

  def set_default_sort_order
    return if sort_order.present? && sort_order > 0

    existing = ControlFamily.unscoped.where(control_catalog_id: control_catalog_id)
    self.sort_order = (existing.maximum(:sort_order) || 0) + 1
  end
end
