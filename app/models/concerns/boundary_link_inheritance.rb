# Inherit cross-document FKs from an AuthorizationBoundary's siblings.
#
# When a document is created with `authorization_boundary_id` set and one
# of its cross-document FKs (e.g. `ssp_document_id` on a SAP) is missing,
# pull the value from the boundary's existing sibling document. Lets the
# upload form's boundary picker (#395 P1) auto-resolve sibling links so
# users don't have to manually `associate_source` after the fact.
#
# Usage:
#   class SapDocument < ApplicationRecord
#     include BoundaryLinkInheritance
#
#     inherits_from_boundary(
#       ssp_document_id:     ->(b) { b.ssp_document&.id },
#       profile_document_id: ->(b) { b.ssp_document&.profile_document_id }
#     )
#   end
#
# The lambda receives the AuthorizationBoundary and returns the value to
# assign (or nil to skip). Existing user-provided FK values are NEVER
# overwritten -- the callback only fills nil columns.
#
# CDEF intentionally does NOT include this concern: CDEFs have no
# authorization_boundary_id column. Their scope is handled separately
# (boundary-specific via boundary_cdef_documents OR globally_available).
module BoundaryLinkInheritance
  extend ActiveSupport::Concern

  class_methods do
    def inherits_from_boundary(map = {})
      @boundary_inheritance_map = map.freeze
    end

    def boundary_inheritance_map
      @boundary_inheritance_map || {}
    end
  end

  included do
    before_validation :inherit_boundary_links
  end

  private

  def inherit_boundary_links
    return if authorization_boundary_id.blank?
    return if self.class.boundary_inheritance_map.empty?

    boundary = AuthorizationBoundary.find_by(id: authorization_boundary_id)
    return if boundary.nil?

    self.class.boundary_inheritance_map.each do |fk_column, source_proc|
      next if public_send(fk_column).present?
      value = source_proc.call(boundary)
      public_send("#{fk_column}=", value) if value.present?
    end
  end
end
