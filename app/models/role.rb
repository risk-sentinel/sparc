# frozen_string_literal: true

# Defines the available roles in SPARC. Roles are either instance-scoped
# (global) or project-scoped. Instance Admin is NOT a role — it's the
# users.admin boolean column.
#
# Seeded roles come from docs/groups_users/groups_users.md:
#   Instance: policy_manager, global_viewer
#   Project:  ao, so_iso, ciso, isso, project_member, assessor_3pao, view_only
class Role < ApplicationRecord
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :name, presence: true, uniqueness: true
  validates :display_name, presence: true
  validates :scope, inclusion: { in: %w[instance project] }

  scope :instance_scoped, -> { where(scope: "instance") }
  scope :project_scoped, -> { where(scope: "project") }
  scope :sorted, -> { order(:sort_order) }
end
