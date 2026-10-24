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

  INSTANCE_SCOPE_REFUSAL =
    "Making a component definition available instance-wide needs cdef.write across the instance " \
    "(Policy Manager or instance administrator).".freeze

  # #1275 — the scopes a submit for review may ask for, and how wide each tier is.
  REQUESTABLE  = %w[global instance].freeze
  REQUEST_TIER = { "global" => :organization, "instance" => :instance }.freeze
  TIER_RANK    = { boundary: 0, organization: 1, instance: 2 }.freeze

  class << self
    # #980/#1257 — instance-wide publishes a CDEF to every organization on the
    # instance, including ones the requester is not a member of, so it needs
    # `cdef.write` held at INSTANCE level: Policy Manager (the only built-in
    # role holding it there) or an instance administrator. A boundary-scoped
    # grant confers nothing here — `has_permission?` with no boundary counts
    # instance-level roles only. Every HTTP surface and the scope picker read this
    # one definition; `apply` itself does not, so the console and the seeds
    # can still use it.
    # NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege).
    def may_scope_instance?(user)
      user.present? && user.has_permission?("cdef.write")
    end

    # scope: "instance" | "global" | "boundary"
    #
    # #980 — the three tiers the CDEF model always described and only ever
    # offered two of:
    #
    #   boundary  globally_available: false + boundary_cdef_documents rows
    #   global    globally_available: true  + organization_id: <the org>
    #   instance  globally_available: true  + organization_id: NULL
    #
    # A NULL organization on an available CDEF means "belongs to no one
    # organization", which is exactly instance-wide. No new column: the encoding
    # was already expressible and `globally_available_in` simply never matched it,
    # so an instance-wide CDEF would have been invisible to every organization
    # rather than visible to all of them.
    #
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
      when "instance" then apply_instance(cdef)
      when "global"   then apply_global(cdef, organization_id: organization_id)
      when "boundary" then apply_boundary(cdef, authorization_boundary_id: authorization_boundary_id)
      else raise ArgumentError, "Unknown CDEF scope: #{scope.inspect}"
      end
    end

    # The authorization boundary this CDEF is currently scoped to, if any.
    def current_boundary_id(cdef)
      (cdef.import_metadata || {})[METADATA_KEY]
    end

    # #1275 — a wider scope asked for at submit for review. Nearly anyone may
    # author a CDEF on their boundary; making it available more widely is an
    # approval at the tier it reaches (owner, 2026-10-24), so the author never
    # needs a wider cdef.write. Who may approve each tier is
    # CdefWriteAccess.may_approve?.
    #
    # The refusal for asking `scope` on this CDEF, or nil when it may be asked.
    def request_refusal(cdef, scope)
      unless REQUESTABLE.include?(scope.to_s)
        return "A wider scope is organization-wide (global) or instance-wide (instance), not #{scope.to_s.inspect}."
      end
      return "This component definition was imported from AWS Labs and is read-only. Use 'Copy' to create an editable clone." if cdef.aws_labs_source?
      if TIER_RANK.fetch(REQUEST_TIER.fetch(scope.to_s)) <= TIER_RANK.fetch(cdef.scope_tier)
        return "This component definition is already available at least that widely."
      end
      if scope.to_s == "global" && requested_organization_id(cdef).nil?
        return "Organization-wide needs an organization, and this component definition's boundary belongs to none."
      end

      nil
    end

    # Applies the scope a CDEF asked for and clears the request. Call inside
    # the approval's transaction; raises ArgumentError as `apply` does.
    def apply_requested!(cdef)
      scope = cdef.requested_scope
      return cdef if scope.blank?

      apply(cdef, scope: scope, organization_id: (requested_organization_id(cdef) if scope == "global"))
      cdef.update!(requested_scope: nil)
      cdef
    end

    # The organization an organization-wide request is for: the one that owns
    # the CDEF's boundary, or failing that the CDEF's own.
    def requested_organization_id(cdef)
      boundary = CdefWriteAccess.boundary_id(cdef)
      (boundary && AuthorizationBoundary.where(id: boundary).pick(:organization_id)) || cdef.organization_id
    end

    private

    # Instance-wide: available to EVERY organization on this instance. The
    # organization is cleared rather than kept, because a CDEF owned by one
    # organization and readable by all is a different (and unmodelled) thing —
    # leaving it set would make the tier indistinguishable from `global` for the
    # owning org and inconsistent for everyone else.
    def apply_instance(cdef)
      ActiveRecord::Base.transaction do
        unlink_previous_boundary(cdef)
        cdef.update!(globally_available: true, organization_id: nil)
        write_metadata_boundary(cdef, nil)
      end
      cdef
    end

    # #1257 — "global" with no organization to own it used to store
    # `globally_available: true, organization_id: NULL`, which IS the instance
    # tier: a requester with `cdef.write` and no organization membership asked
    # for organization-wide and made the CDEF instance-wide, past the #980
    # refusal of "instance". Organization-wide now needs an organization.
    def apply_global(cdef, organization_id:)
      owner = organization_id || cdef.organization_id
      if owner.nil?
        raise ArgumentError,
              "Organization-wide needs an organization to own the component definition, " \
              "and none was found. Join an organization, or choose a boundary."
      end

      ActiveRecord::Base.transaction do
        unlink_previous_boundary(cdef)
        cdef.update!(globally_available: true, organization_id: owner)
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
