# frozen_string_literal: true

# Join model linking Users to Organizations with an org-level role.
# Roles follow the senior official pattern used by instance-scoped roles
# (Head of Agency, CIO, CISO, etc.) plus org_admin and generic member.
#
# The role list is configurable via SPARC_ORGANIZATION_ROLES env var.
# org_admin is a fixed system role — always available regardless of config.
class OrganizationMembership < ApplicationRecord
  # Fixed system role — always available, cannot be removed via env var
  SYSTEM_ROLES = %w[org_admin].freeze

  # Default configurable roles (used when SPARC_ORGANIZATION_ROLES is not set)
  DEFAULT_ROLES = %w[
    head_of_agency
    senior_accountable_official
    cio
    ciso
    risk_executive
    chief_acquisition_officer
    senior_agency_official_privacy
    member
  ].freeze

  # Backward compatibility
  ROLES = (SYSTEM_ROLES + DEFAULT_ROLES).freeze

  DEFAULT_ROLE_LABELS = {
    "org_admin"                      => "Org Admin",
    "head_of_agency"                 => "Head of Agency",
    "senior_accountable_official"    => "Senior Accountable Official",
    "cio"                            => "CIO",
    "ciso"                           => "CISO",
    "risk_executive"                 => "Risk Executive",
    "chief_acquisition_officer"      => "Chief Acquisition Officer",
    "senior_agency_official_privacy" => "Senior Agency Official for Privacy",
    "member"                         => "Member"
  }.freeze

  belongs_to :organization
  belongs_to :user

  validates :user_id, uniqueness: { scope: :organization_id, message: "is already a member of this organization" }
  validates :role, inclusion: { in: ->(record) { record.class.available_roles } }

  # Returns the full list of available roles (system + configured).
  # Roles from env vars are used as-is (display names accepted).
  def self.available_roles
    configured = SparcConfig.organization_roles
    (SYSTEM_ROLES + configured).uniq
  end

  # Returns role options for select dropdowns: [[label, value], ...]
  def self.role_options
    available_roles.map { |r| [ role_label_for(r), r ] }
  end

  # Human-readable label for any role
  def self.role_label_for(role)
    DEFAULT_ROLE_LABELS[role] || role.to_s.titleize
  end

  # Instance method for convenience
  def role_label
    self.class.role_label_for(role)
  end
end
