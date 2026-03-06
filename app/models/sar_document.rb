class SarDocument < ApplicationRecord
  has_many :sar_controls, dependent: :delete_all
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json] }

  def to_json_data
    {
      document_name: name,
      controls: sar_controls.order(:row_order).includes(:sar_control_fields).map(&:to_hash)
    }
  end
end
