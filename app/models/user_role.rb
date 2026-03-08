# frozen_string_literal: true

# Join model linking Users to Roles, optionally scoped to a project.
# When project_id is NULL, the role applies instance-wide.
class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :project, optional: true

  validates :user_id, uniqueness: { scope: [ :role_id, :project_id ] }
  validate :role_scope_matches_project

  private

  def role_scope_matches_project
    return unless role

    if project_id.present? && role.scope == "instance"
      errors.add(:role, "is instance-scoped and cannot be assigned to a project")
    end
    if project_id.nil? && role.scope == "project"
      errors.add(:role, "is project-scoped and requires a project")
    end
  end
end
