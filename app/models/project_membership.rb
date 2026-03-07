class ProjectMembership < ApplicationRecord
  belongs_to :project

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
end
