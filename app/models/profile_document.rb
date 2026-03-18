class ProfileDocument < ApplicationRecord
  include OscalMetadata
  include SafeDestroyable
  include Sluggable
  include Lifecycle

  has_many :profile_controls, dependent: :delete_all
  belongs_to :control_catalog, optional: true
  belongs_to :source_profile, class_name: "ProfileDocument", optional: true
  has_many :derived_profiles, class_name: "ProfileDocument", foreign_key: :source_profile_id
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

  private

  def deletion_dependencies
    deps = []
    ssp_count = SspDocument.where(profile_document_id: id).count
    deps << "#{ssp_count} SSP(s)" if ssp_count > 0
    sar_count = SarDocument.where(profile_document_id: id).count
    deps << "#{sar_count} Assessment Result(s)" if sar_count > 0
    sap_count = SapDocument.where(profile_document_id: id).count
    deps << "#{sap_count} Assessment Plan(s)" if sap_count > 0
    derived_count = derived_profiles.count
    deps << "#{derived_count} derived profile(s)" if derived_count > 0
    deps
  end
end
