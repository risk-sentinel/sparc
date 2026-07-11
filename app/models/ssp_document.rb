class SspDocument < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include UploadTrackable
  include BoundaryLinkInheritance
  include ContentCompleteness

  # #557 — belt-and-suspenders for the API-create path. The DB default
  # now backstops this, but the after_initialize ensures Rails console
  # / jobs / direct `SspDocument.new` get the same default behavior.
  after_initialize { self.status ||= "pending" }

  belongs_to :authorization_boundary, optional: true

  # #395 P2: inherit profile_document_id from the boundary's profile when
  # not user-provided. Runs before_validation; nil-result is a no-op.
  inherits_from_boundary(
    profile_document_id: ->(b) { b.profile_document_id }
  )

  include AttachmentSizeLimit

  has_many :ssp_controls, dependent: :destroy
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  # OSCAL entity associations
  has_many :ssp_information_types, dependent: :delete_all
  has_many :ssp_components, dependent: :delete_all
  has_many :ssp_users, dependent: :delete_all
  has_many :ssp_leveraged_authorizations, dependent: :delete_all
  has_many :ssp_inventory_items, dependent: :delete_all
  has_many :ssp_by_components, through: :ssp_controls

  # Source linkages
  belongs_to :profile_document, optional: true
  has_many :sar_documents, dependent: :nullify
  has_many :ssp_document_cdef_documents, dependent: :delete_all
  has_many :cdef_documents, through: :ssp_document_cdef_documents

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json xml yaml] }, allow_nil: true
  validates :creation_method, inclusion: { in: %w[excel wizard oscal_import profile] }, allow_nil: true

  CREATION_METHODS = %w[excel wizard oscal_import profile].freeze
  SYSTEM_STATUSES = %w[operational under-development under-major-modification disposition other].freeze
  SENSITIVITY_LEVELS = %w[fips-199-low fips-199-moderate fips-199-high].freeze

  # #627 — content-completeness, independent of the parse `status`. An SSP
  # needs system characteristics (at minimum) and at least one control before
  # it can be published; a metadata-only API create satisfies neither.
  requires_content("System characteristics") do
    system_id.present? || system_name_short.present? || security_sensitivity_level.present?
  end
  requires_content("At least one control") { ssp_controls.exists? }

  def wizard_created?
    creation_method == "wizard"
  end

  def oscal_imported?
    creation_method == "oscal_import"
  end

  def profile_created?
    creation_method == "profile"
  end

  def enriched?
    description.present? ||
      ssp_components.exists? ||
      ssp_information_types.exists? ||
      ssp_users.exists? ||
      security_sensitivity_level.present?
  end

  def to_json_data
    {
      document_name: name,
      controls: ssp_controls.includes(:ssp_control_fields).map(&:to_hash)
    }
  end

  def self.from_excel(file_path, original_filename)
    document = create!(
      name: File.basename(original_filename, ".*"),
      file_type: "excel",
      original_filename: original_filename,
      status: "processing"
    )

    SspExcelParserService.new(document, file_path).parse
    document.update!(status: "completed")
    document
  rescue StandardError => e
    document&.update!(status: "failed")
    raise e
  end

  private

  def deletion_dependencies
    deps = []
    sap_count = SapDocument.where(ssp_document_id: id).count
    deps << "#{sap_count} Assessment Plan(s)" if sap_count > 0
    sar_count = SarDocument.where(ssp_document_id: id).count
    deps << "#{sar_count} Assessment Result(s)" if sar_count > 0
    deps
  end
end
