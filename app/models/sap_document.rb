class SapDocument < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include UploadTrackable
  include BoundaryLinkInheritance

  belongs_to :authorization_boundary, optional: true

  include BoundaryReferenceValidation

  include AttachmentSizeLimit

  has_many :sap_controls, dependent: :delete_all
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  belongs_to :ssp_document, optional: true

  # #911 layer 2 — OSCAL requires `import-ssp` on an assessment plan. You cannot
  # say what was assessed without naming the system security plan it assessed.
  include CatalogLineage
  lineage_via :ssp_document,
              key:     :ssp,
              label:   "SSP",
              remedy:  "PATCH /api/v1/sap_documents/:id { ssp_document_id }",
              options: "/api/v1/ssp_documents",
              controls: :sap_controls
  belongs_to :profile_document, optional: true
  include ControlMembership
  membership_within controls: :sap_controls, baseline: :ssp_document,
                    baseline_controls: :ssp_controls,
                    label: "assessed SSP"

  # Inherit cross-document FKs from the boundary's existing siblings on save
  # (#395 P1). User-supplied values take precedence; we only fill nil columns.
  inherits_from_boundary(
    ssp_document_id:     ->(b) { b.ssp_document&.id },
    profile_document_id: ->(b) { b.ssp_document&.profile_document_id }
  )

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  ASSESSMENT_TYPES = %w[initial annual continuous ad-hoc].freeze
  ASSESSMENT_METHODS = %w[examine interview test].freeze

  def to_json_data
    {
      document_name: name,
      sap_version: sap_version,
      description: description,
      assessment_type: assessment_type,
      assessment_start: assessment_start,
      assessment_end: assessment_end,
      assessors: assessors,
      assessment_scope: assessment_scope,
      ssp_document_name: ssp_document&.name,
      profile_document_name: profile_document&.name,
      controls: sap_controls.order(:row_order).includes(:sap_control_fields).map(&:to_hash)
    }
  end

  def method_counts
    sap_controls.group(:assessment_method).count
  end

  def status_counts
    sap_controls.group(:assessment_status).count
  end

  private

  def deletion_dependencies
    deps = []
    sar_count = SarDocument.where(sap_document_id: id).count
    deps << "#{sar_count} SAR(s)" if sar_count > 0
    deps
  end
end
