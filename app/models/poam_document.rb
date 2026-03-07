class PoamDocument < ApplicationRecord
  has_many :poam_items, dependent: :delete_all
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  RISK_STATUSES = %w[open deviation-approved closed].freeze

  def to_json_data
    {
      document_name: name,
      poam_version: poam_version,
      oscal_version: oscal_version,
      system_id: system_id,
      items: poam_items.order(:row_order).includes(:poam_item_fields).map(&:to_hash)
    }
  end
end
