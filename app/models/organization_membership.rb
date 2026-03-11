# frozen_string_literal: true

# Join model linking Users to Organizations with an org-level role.
# Roles follow the senior official pattern used by instance-scoped roles
# (Head of Agency, CIO, CISO, etc.) plus org_admin and generic member.
class OrganizationMembership < ApplicationRecord
  ROLES = %w[
    org_admin
    head_of_agency
    senior_accountable_official
    cio
    ciso
    risk_executive
    chief_acquisition_officer
    senior_agency_official_privacy
    member
  ].freeze

  ROLE_LABELS = {
    "org_admin"                     => "Org Admin",
    "head_of_agency"                => "Head of Agency",
    "senior_accountable_official"   => "Senior Accountable Official",
    "cio"                           => "CIO",
    "ciso"                          => "CISO",
    "risk_executive"                => "Risk Executive",
    "chief_acquisition_officer"     => "Chief Acquisition Officer",
    "senior_agency_official_privacy" => "Senior Agency Official for Privacy",
    "member"                        => "Member"
  }.freeze

  belongs_to :organization
  belongs_to :user

  validates :user_id, uniqueness: { scope: :organization_id, message: "is already a member of this organization" }
  validates :role, inclusion: { in: ROLES }

  # Human-readable role label
  def role_label
    ROLE_LABELS[role] || role.titleize
  end
end
