# frozen_string_literal: true

# Apply a CDEF's scope choice — boundary-specific or globally available (#929).
#
# CDEF is the odd one out among the document types. It has no
# `authorization_boundary_id` column at all: a component definition reaches a
# boundary through `boundary_cdef_documents` rows against that boundary's
# sub-Boundary (environment) records, or is marked `globally_available` so any
# boundary's SSP composition can compose it.
#
# That scope was applied only at upload, inline in
# `FileUploadable#apply_post_create_scope!`, and no route changed it afterwards
# — the same defect #929 reports for the other four types, in a different
# mechanism. Extracted here so create and update share one implementation.
#
# Re-pointing removes only the links belonging to the PREVIOUSLY recorded
# authorization boundary. Environments can also be given CDEFs directly from the
# boundary's own form (`BoundariesController#sync_cdef_documents`), so clearing
# every `boundary_cdef_documents` row would silently destroy assignments this
# service never made.
#
# NIST 800-53: AC-3 Access Enforcement, CM-6 Configuration Settings.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class CdefScopeService
  METADATA_KEY = "authorization_boundary_id"

  class << self
    # scope: "global" | "boundary"
    # Returns the CDEF. Raises ArgumentError on an unusable combination, so a
    # caller cannot half-apply a scope.
    def apply(cdef, scope:, authorization_boundary_id: nil, organization_id: nil)
      # #466 — AWS Labs CDEFs are upstream content and read-only. Scope is not
      # OSCAL content, but re-scoping one flips `globally_available` on a
      # document the refresh job owns, which would quietly remove it from every
      # other boundary's composition and be undone by the next refresh. Clone
      # it and scope the clone, exactly as `ensure_editable!` directs.
      if cdef.respond_to?(:aws_labs_source?) && cdef.aws_labs_source?
        raise ArgumentError,
              "This component definition was imported from AWS Labs and is read-only. " \
              "Use 'Copy' to create an editable clone."
      end

      case scope.to_s
      when "global"   then apply_global(cdef, organization_id: organization_id)
      when "boundary" then apply_boundary(cdef, authorization_boundary_id: authorization_boundary_id)
      else raise ArgumentError, "Unknown CDEF scope: #{scope.inspect}"
      end
    end

    # The authorization boundary this CDEF is currently scoped to, if any.
    def current_boundary_id(cdef)
      (cdef.import_metadata || {})[METADATA_KEY]
    end

    private

    def apply_global(cdef, organization_id:)
      ActiveRecord::Base.transaction do
        unlink_previous_boundary(cdef)
        cdef.update!(globally_available: true, organization_id: organization_id || cdef.organization_id)
        write_metadata_boundary(cdef, nil)
      end
      cdef
    end

    def apply_boundary(cdef, authorization_boundary_id:)
      boundary_id = authorization_boundary_id.presence
      raise ArgumentError, "A boundary-specific CDEF needs an authorization boundary" if boundary_id.blank?

      target = AuthorizationBoundary.find_by(id: boundary_id)
      raise ArgumentError, "That authorization boundary no longer exists" if target.nil?

      ActiveRecord::Base.transaction do
        unlink_previous_boundary(cdef)
        cdef.update!(globally_available: false)

        Boundary.where(authorization_boundary_id: target.id).ids.each do |sub_boundary_id|
          BoundaryCdefDocument.find_or_create_by!(boundary_id: sub_boundary_id, cdef_document_id: cdef.id)
        end

        # There is no FK to hold this, and the show page needs to name the
        # boundary a CDEF belongs to.
        write_metadata_boundary(cdef, target.id)
      end
      cdef
    end

    # Drops only the links this service created for the previously recorded
    # boundary. A link added from the environment's own form survives.
    def unlink_previous_boundary(cdef)
      previous_id = current_boundary_id(cdef)
      return if previous_id.blank?

      sub_boundary_ids = Boundary.where(authorization_boundary_id: previous_id).ids
      return if sub_boundary_ids.empty?

      BoundaryCdefDocument.where(cdef_document_id: cdef.id, boundary_id: sub_boundary_ids).delete_all
    end

    def write_metadata_boundary(cdef, boundary_id)
      metadata = (cdef.import_metadata || {}).dup
      if boundary_id.nil?
        metadata.delete(METADATA_KEY)
      else
        metadata[METADATA_KEY] = boundary_id.to_i
      end
      cdef.update_column(:import_metadata, metadata)
    end
  end
end
