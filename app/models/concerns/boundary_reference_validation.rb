# frozen_string_literal: true

# Rejects a reference to an authorization boundary that does not exist.
#
# These documents declare `belongs_to :authorization_boundary, optional: true`,
# which makes the association OPTIONAL — it does not make a supplied id VALID.
# When a caller sent an id with no matching row, the association resolved to nil
# but the id was still written, so PostgreSQL raised
# ActiveRecord::InvalidForeignKey (PG::ForeignKeyViolation). Nothing rescued it,
# so `POST /api/v1/ssp_documents` with a stale boundary id answered 500 — an
# unhandled server error for what is ordinary bad input.
#
# Validating here (rather than rescuing in one controller) covers every entry
# point — API, UI, importers, background jobs — and returns a field-level error
# the client can act on.
#
# NIST 800-53: SI-10 (information input validation).
module BoundaryReferenceValidation
  extend ActiveSupport::Concern

  included do
    validate :authorization_boundary_must_exist
  end

  private

  def authorization_boundary_must_exist
    return if authorization_boundary_id.blank?
    return if AuthorizationBoundary.exists?(authorization_boundary_id)

    errors.add(:authorization_boundary_id, "references a boundary that does not exist")
  end
end
