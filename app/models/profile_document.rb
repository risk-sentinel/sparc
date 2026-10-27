class ProfileDocument < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include UploadTrackable
  include ContentCompleteness
  include Approvable

  has_many :profile_controls, dependent: :delete_all
  # #1089 — the component definitions used under this baseline.
  has_many :cdef_document_profile_documents, dependent: :delete_all
  has_many :cdef_documents, through: :cdef_document_profile_documents
  belongs_to :control_catalog, optional: true

  # #911 layer 2 — a profile does not merely HAVE a catalog, it imports a
  # selection from one. This is the root of the chain: a profile whose import
  # cannot be mapped back is broken at the root, and every SSP, SAP and SAR
  # beneath it inherits that.
  include CatalogLineage
  lineage_via :control_catalog,
              key:      :catalog,
              controls: :profile_controls,
              message:  { label:   "catalog",
                          remedy:  "Choose the control catalog this profile draws its controls from.",
                          options: "/api/v1/control_catalogs" }
  include AttachmentSizeLimit
  include ControlMembership
  membership_within controls: :profile_controls, baseline: :control_catalog,
                    baseline_controls: :catalog_controls,
                    label: "catalog"

  belongs_to :source_profile, class_name: "ProfileDocument", optional: true
  has_many :derived_profiles, class_name: "ProfileDocument", foreign_key: :source_profile_id
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  # Baselines an SSP can be built from: published, so the SSP answers a fixed
  # baseline, and resolved, because the SSP's statement parts are read from the
  # resolved catalog publishing produces (SspFromProfileService). The SSP
  # wizard, "Create from profile" and "Populate from profile" all offer these.
  scope :ssp_ready, -> { where(lifecycle_status: "published").where.not(resolved_catalog_json: nil) }

  BASELINE_LEVELS = %w[LOW MODERATE HIGH].freeze

  # #627 — content-completeness, independent of the parse `status`. A profile
  # tailors a catalog, so it needs a linked catalog and at least one control
  # before it can be published; a metadata-only API create has neither.
  requires_content("A linked control catalog") { control_catalog_id.present? }
  # Upload's match to a loaded catalog is a suggestion until a person confirms
  # or changes it (ProfileCatalogLinkService).
  requires_content("A confirmed control catalog") { !catalog_confirmation_pending? }
  requires_content("At least one control") { profile_controls.exists? }

  # Upload linked this baseline to a catalog it matched, and no one has
  # confirmed or changed it yet. A baseline with no such record (authored,
  # created from a catalog, or uploaded before the confirmation step) is not
  # pending.
  def catalog_confirmation_pending?
    import_metadata.is_a?(Hash) && import_metadata["catalog_confirmation"] == "pending"
  end

  # How upload matched the catalog this baseline is linked to ("uuid",
  # "nist_pattern", "title"), for the confirmation prompt.
  def suggested_catalog_match
    Array(import_metadata.is_a?(Hash) ? import_metadata["imports"] : nil)
      .find { |imp| imp["catalog_id"] == control_catalog_id }&.dig("matched_by")
  end

  # A person declared this baseline's catalog: the web picker (set_baseline)
  # and PATCH /api/v1/profile_documents/:id both land here. Re-checks the
  # imports against it and marks the link confirmed.
  def baseline_declared!
    ProfileCatalogLinkService.new(self).call
  end

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
