class CdefDocument < ApplicationRecord
  include OscalMetadata
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable

  # CDEF intentionally does NOT include BoundaryLinkInheritance: it has
  # no authorization_boundary_id column. Scope is handled at the
  # controller layer via the global-vs-boundary picker (#395 P1) which
  # writes globally_available + organization_id or attaches via
  # boundary_cdef_documents.

  has_many :cdef_controls, dependent: :delete_all
  has_many :boundary_cdef_documents, dependent: :destroy
  has_many :boundaries, through: :boundary_cdef_documents
  belongs_to :profile_document, optional: true
  belongs_to :organization, optional: true
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  # Scope: CDEFs visible to a given organization for SSP composition.
  # Returns globally_available CDEFs in that org. (Boundary-specific CDEFs
  # are reached via the boundary's `boundaries.cdef_documents` association.)
  scope :globally_available_in, ->(org) {
    where(globally_available: true, organization_id: org&.id)
  }

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

  private

  def deletion_dependencies
    deps = []
    ssp_count = SspDocumentCdefDocument.where(cdef_document_id: id).count
    deps << "#{ssp_count} SSP(s)" if ssp_count > 0
    boundary_count = BoundaryCdefDocument.where(cdef_document_id: id).count
    deps << "#{boundary_count} boundary environment(s)" if boundary_count > 0
    deps
  end
end
