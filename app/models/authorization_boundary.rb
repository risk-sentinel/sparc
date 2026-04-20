class AuthorizationBoundary < ApplicationRecord
  include Sluggable
  belongs_to :organization, optional: true
  belongs_to :profile_document, optional: true   # #395 P3: one baseline per system
  has_many :boundaries, dependent: :destroy
  has_many :authorization_boundary_memberships, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :assigned_users, through: :user_roles, source: :user
  has_many :cdef_documents, through: :boundaries

  has_one  :ssp_document, dependent: :nullify
  has_one  :sap_document, dependent: :nullify
  has_one  :sar_document, dependent: :nullify
  has_many :poam_documents, dependent: :nullify
  has_many :evidences, dependent: :nullify
  has_many :ksi_validations, dependent: :destroy

  enum :status, {
    draft: "draft",
    active: "active",
    authorized: "authorized",
    deauthorized: "deauthorized"
  }

  # #395 P3: the uuid column has a gen_random_uuid() default at the DB
  # level, but validations run before the INSERT populates it. Fill the
  # UUID on before_validation so v4 format validation passes on create.
  before_validation :assign_uuid_if_blank

  validates :name, presence: true
  validates :status, presence: true
  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }

  STATUSES = %w[draft active authorized deauthorized].freeze

  # #395 P3: single source of truth for system-level metadata. Documents
  # read these via BoundaryMetadataSyncService at edit/render time. Each
  # key maps to a setter on the document side via FIELD_TO_SETTER.
  BOUNDARY_METADATA_KEYS = %w[
    system_title short_name impact_level
    authorization_date authorization_status
    authorizing_official system_owner isso issm assessor
  ].freeze

  BOUNDARY_METADATA_KEYS.each do |key|
    define_method(key) { (boundary_metadata || {})[key] }
    define_method("#{key}=") { |v|
      self.boundary_metadata = (boundary_metadata || {}).merge(key => v)
    }
  end

  def linked_documents
    [ ssp_document, sap_document, sar_document, profile_document, *poam_documents ].compact
  end

  def metadata_drift_for(document)
    BoundaryMetadataSyncService.new(self).drift_for(document)
  end

  def metadata_status_for(document)
    BoundaryMetadataSyncService.new(self).status_for(document)
  end

  def artifact_summary
    {
      ssp: ssp_document&.name,
      sap: sap_document&.name,
      sar: sar_document&.name,
      poam_count: poam_documents.count,
      boundary_count: boundaries.count,
      component_count: boundaries.joins(:cdef_documents).count
    }
  end

  def members_by_role
    authorization_boundary_memberships.order(:role, :user_name).group_by(&:role)
  end

  private

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end
end
