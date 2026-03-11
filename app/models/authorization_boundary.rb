class AuthorizationBoundary < ApplicationRecord
  belongs_to :organization, optional: true
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

  enum :status, {
    draft: "draft",
    active: "active",
    authorized: "authorized",
    deauthorized: "deauthorized"
  }

  validates :name, presence: true
  validates :status, presence: true

  STATUSES = %w[draft active authorized deauthorized].freeze

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
end
