# Legacy membership model for authorization boundaries.
# Role list is configurable via SPARC_AUTH_BOUNDARY_ROLES env var.
#
# Note: The system is transitioning to UserRole + Role for boundary
# memberships. This model supports legacy memberships with string roles.
class AuthorizationBoundaryMembership < ApplicationRecord
  belongs_to :authorization_boundary
  belongs_to :user, optional: true

  # Default roles (used when SPARC_AUTH_BOUNDARY_ROLES is not set)
  DEFAULT_ROLES = %w[
    authorizing_official
    system_owner
    ciso
    isso
    project_member
    assessor
    view_only
  ].freeze

  # Backward compatibility
  ROLES = DEFAULT_ROLES

  DEFAULT_ROLE_LABELS = {
    "authorizing_official" => "Authorizing Official (AO)",
    "system_owner"         => "System Owner (SO/ISO)",
    "ciso"                 => "CISO",
    "isso"                 => "ISSO",
    "project_member"       => "Team Member",
    "assessor"             => "Assessor / 3PAO",
    "view_only"            => "View Only"
  }.freeze

  enum :role, DEFAULT_ROLES.index_with(&:itself)

  validates :user_name, presence: true
  validates :role, presence: true

  # Returns the configured list of available roles
  def self.available_roles
    SparcConfig.auth_boundary_roles
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

  # Link this legacy membership to a User record by matching email.
  # Returns true if linked, false if no matching user found.
  def link_to_user!
    return true if user_id.present?

    matched_user = User.find_by("LOWER(email) = ?", user_email.to_s.downcase.strip)
    if matched_user
      update!(user_id: matched_user.id)
      true
    else
      false
    end
  end
end
