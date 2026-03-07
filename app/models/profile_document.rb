class ProfileDocument < ApplicationRecord
  has_many :profile_controls, dependent: :delete_all
  belongs_to :control_catalog, optional: true
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  BASELINE_LEVELS = %w[LOW MODERATE HIGH].freeze

  def to_json_data
    {
      document_name: name,
      baseline_level: baseline_level,
      profile_version: profile_version,
      oscal_version: oscal_version,
      description: description,
      catalog_name: control_catalog&.name,
      controls: profile_controls.order(:row_order).includes(:profile_control_fields).map(&:to_hash)
    }
  end
end
