class ProfileDocument < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include ContentCompleteness
  include Approvable

  has_many :profile_controls, dependent: :delete_all
  belongs_to :control_catalog, optional: true
  include AttachmentSizeLimit

  belongs_to :source_profile, class_name: "ProfileDocument", optional: true
  has_many :derived_profiles, class_name: "ProfileDocument", foreign_key: :source_profile_id
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  BASELINE_LEVELS = %w[LOW MODERATE HIGH].freeze

  # #627 — content-completeness, independent of the parse `status`. A profile
  # tailors a catalog, so it needs a linked catalog and at least one control
  # before it can be published; a metadata-only API create has neither.
  requires_content("A linked control catalog") { control_catalog_id.present? }
  requires_content("At least one control") { profile_controls.exists? }

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
