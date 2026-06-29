class PoamDocument < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include BoundaryLinkInheritance

  belongs_to :authorization_boundary, optional: true
  belongs_to :ssp_document, optional: true   # #395 P2: link to remediation source

  # #395 P2: inherit ssp_document_id from the boundary's SSP when not
  # user-provided. Runs before_validation; nil-result is a no-op.
  inherits_from_boundary(
    ssp_document_id: ->(b) { b.ssp_document&.id }
  )

  has_many :poam_items, dependent: :delete_all
  has_many :poam_risks, dependent: :delete_all
  has_many :poam_observations, dependent: :delete_all
  include AttachmentSizeLimit

  has_many :poam_findings, dependent: :delete_all
  has_many :poam_local_components, dependent: :delete_all
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  RISK_STATUSES = %w[open investigating remediating deviation-requested deviation-approved closed].freeze

  def to_json_data
    {
      document_name: name,
      poam_version: poam_version,
      oscal_version: oscal_version,
      system_id: system_id,
      risks_count: poam_risks.count,
      observations_count: poam_observations.count,
      findings_count: poam_findings.count,
      items: poam_items.order(:row_order).map(&:to_hash)
    }
  end
end
