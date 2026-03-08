class ProjectMembership < ApplicationRecord
  belongs_to :project
  belongs_to :user, optional: true

  ROLES = %w[
    authorizing_official
    system_owner
    ciso
    isso
    project_member
    assessor
    view_only
  ].freeze

  ROLE_LABELS = {
    "authorizing_official" => "Authorizing Official (AO)",
    "system_owner"         => "System Owner (SO/ISO)",
    "ciso"                 => "CISO",
    "isso"                 => "ISSO",
    "project_member"       => "Project Member",
    "assessor"             => "Assessor / 3PAO",
    "view_only"            => "View Only"
  }.freeze

  enum :role, ROLES.index_with(&:itself)

  validates :user_name, presence: true
  validates :role, presence: true

  def role_label
    ROLE_LABELS[role] || role.titleize
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
