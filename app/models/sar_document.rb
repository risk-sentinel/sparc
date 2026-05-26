class SarDocument < ApplicationRecord
  include OscalMetadata
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include BoundaryLinkInheritance

  # #557 — belt-and-suspenders for the API-create path. See SspDocument
  # for the same fix.
  after_initialize { self.status ||= "pending" }

  belongs_to :authorization_boundary, optional: true

  has_many :sar_controls, dependent: :delete_all
  include AttachmentSizeLimit

  has_many :sar_results, dependent: :delete_all
  has_many :sar_local_components, dependent: :delete_all
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  belongs_to :sap_document, optional: true
  belongs_to :profile_document, optional: true
  belongs_to :ssp_document, optional: true

  # Inherit cross-document FKs from the boundary's existing siblings on save
  # (#395 P1). User-supplied values take precedence; we only fill nil columns.
  inherits_from_boundary(
    sap_document_id:     ->(b) { b.sap_document&.id },
    ssp_document_id:     ->(b) { b.ssp_document&.id },
    profile_document_id: ->(b) { b.ssp_document&.profile_document_id }
  )

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json xml yaml] }, allow_nil: true
  validates :creation_method, inclusion: { in: %w[excel wizard oscal_import profile ssp] }, allow_nil: true

  CREATION_METHODS = %w[excel wizard oscal_import profile ssp].freeze

  def wizard_created?
    creation_method == "wizard"
  end

  def oscal_imported?
    creation_method == "oscal_import"
  end

  def profile_created?
    creation_method == "profile"
  end

  def ssp_created?
    creation_method == "ssp"
  end

  def enriched?
    description.present? ||
      sar_results.exists? ||
      sar_local_components.exists? ||
      import_ap_href.present?
  end

  def to_json_data
    {
      document_name: name,
      controls: sar_controls.order(:row_order).includes(:sar_control_fields).map(&:to_hash)
    }
  end
end
