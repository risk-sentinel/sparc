# frozen_string_literal: true

# Join model linking Users to Roles, optionally scoped to a project.
# When project_id is NULL, the role applies instance-wide.
class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role

  validates :user_id, uniqueness: { scope: [ :role_id, :project_id ] }
end
