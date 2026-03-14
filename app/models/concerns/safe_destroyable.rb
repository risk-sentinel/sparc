# frozen_string_literal: true

# Prevents accidental deletion of records that are referenced by other documents.
#
# Including models must define a `deletion_dependencies` method that returns
# an array of human-readable strings describing active references.
# Example: ["2 SSP(s)", "1 Assessment Plan(s)"]
#
# If dependencies exist, the destroy is aborted and an error is added to :base.
#
# Usage:
#   class ProfileDocument < ApplicationRecord
#     include SafeDestroyable
#
#     private
#
#     def deletion_dependencies
#       deps = []
#       deps << "#{SspDocument.where(profile_document_id: id).count} SSP(s)" if SspDocument.where(profile_document_id: id).exists?
#       deps
#     end
#   end
module SafeDestroyable
  extend ActiveSupport::Concern

  included do
    # Declared before associations with dependent: options so it runs first.
    before_destroy :check_deletion_dependencies
  end

  private

  # Override in each model to return an array of dependency description strings.
  # Return an empty array if no dependencies exist.
  def deletion_dependencies
    []
  end

  def check_deletion_dependencies
    deps = deletion_dependencies
    return if deps.empty?

    entity_label = self.class.name.underscore.humanize.downcase
    errors.add(:base, "Cannot delete #{entity_label}: linked to #{deps.join(', ')}")
    throw(:abort)
  end
end
