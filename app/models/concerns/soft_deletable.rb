# Soft-delete support for document models.
#
# Adds a `deleted_at` timestamp column that marks records as deleted
# without physically removing them. Provides scopes, predicates,
# and restore capability.
#
# Usage:
#   include SoftDeletable
#
# Requires a `deleted_at` datetime column on the table.
#
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    default_scope { where(deleted_at: nil) }

    scope :with_deleted, -> { unscope(where: :deleted_at) }
    scope :only_deleted, -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }
  end

  def soft_delete!
    update_columns(deleted_at: Time.current)
  end

  def restore!
    update_columns(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end
end
