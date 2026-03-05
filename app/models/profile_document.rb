class ProfileDocument < ApplicationRecord
  has_many :profile_controls, dependent: :delete_all
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  PROFILE_TYPES = %w[disa_stig scap cis custom].freeze

  def to_json_data
    {
      document_name: name,
      profile_type: profile_type,
      profile_version: profile_version,
      benchmark_id: benchmark_id,
      description: description,
      controls: profile_controls.order(:row_order).includes(:profile_control_fields).map(&:to_hash)
    }
  end
end
