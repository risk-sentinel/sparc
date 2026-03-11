# frozen_string_literal: true

# Join model linking Users to Roles, optionally scoped to an authorization boundary.
# When authorization_boundary_id is NULL, the role applies instance-wide.
class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :authorization_boundary, optional: true

  validates :user_id, uniqueness: { scope: [ :role_id, :authorization_boundary_id ] }
  validate :role_scope_matches_authorization_boundary

  private

  def role_scope_matches_authorization_boundary
    return unless role

    if authorization_boundary_id.present? && role.scope == "instance"
      errors.add(:role, "is instance-scoped and cannot be assigned to an authorization boundary")
    end
    if authorization_boundary_id.nil? && role.scope == "authorization_boundary"
      errors.add(:role, "is authorization boundary-scoped and requires an authorization boundary")
    end
  end
end
