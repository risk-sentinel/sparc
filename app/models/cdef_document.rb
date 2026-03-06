class CdefDocument < ApplicationRecord
  has_many :cdef_controls, dependent: :delete_all
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  CDEF_TYPES = %w[disa_stig scap cis custom].freeze

  def to_json_data
    {
      document_name: name,
      cdef_type: cdef_type,
      cdef_version: cdef_version,
      benchmark_id: benchmark_id,
      description: description,
      controls: cdef_controls.order(:row_order).includes(:cdef_control_fields).map(&:to_hash)
    }
  end
end
