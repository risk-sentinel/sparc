# frozen_string_literal: true

# #1258 — the CDEF write guards the web controller and
# Api::V1::CdefDocumentsController both include. CdefWriteAccess is the rule;
# this applies it to a request.
#
# The including controller supplies:
#   cdef_write_target       the CDEF being written
#   cdef_scope_params       [scope, authorization_boundary_id] as the request
#                           sent them, from the SAME place the action applies
#                           them, so the guard and the write cannot disagree
#
# Each guard honours SparcConfig.any_auth_enabled? and raises
# NotAuthorizedError, so the refusal is audited and answered as every other
# authorization failure (web: redirect; API: 403).
#
# NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege).
module CdefWriteGuards
  extend ActiveSupport::Concern

  private

  def authorize_cdef_write!
    return unless SparcConfig.any_auth_enabled?
    return if CdefWriteAccess.may_write?(current_user, cdef_write_target)

    raise Authorization::NotAuthorizedError, "Permission 'cdef.write' required on this component definition's boundary"
  end

  # Where a CDEF is going: a new one (create, import, copy, from a profile), or
  # the target of a scope change, which authorize_cdef_write! has already
  # checked as it is now. An instance-level writer may use every tier; anyone
  # else only a boundary they hold cdef.write on.
  def authorize_cdef_destination!
    return unless SparcConfig.any_auth_enabled?
    return if CdefWriteAccess.instance_writer?(current_user)

    scope, boundary_id = requested_cdef_scope
    return if CdefWriteAccess.may_scope?(current_user, scope, boundary_id)

    raise Authorization::NotAuthorizedError, CdefWriteAccess.scope_refusal(scope)
  end

  # The requested scope. A boundary-only writer who names none gets the one
  # boundary it can only be: on a copy, the source's boundary when they write
  # there; otherwise their only writable boundary. (The Copy button sends no
  # scope.) Anyone else with no scope named is refused by the guard.
  def requested_cdef_scope
    @requested_cdef_scope ||= begin
      scope, boundary_id = cdef_scope_params
      scope = scope.presence
      boundary_id = boundary_id.presence
      # "Boundary-specific" with no boundary picked is the picker's default,
      # not a choice.
      scope = nil if scope == "boundary" && boundary_id.nil?
      if scope.nil? && current_user && !CdefWriteAccess.instance_writer?(current_user)
        default = default_cdef_boundary_id
        scope, boundary_id = "boundary", default if default
      end
      [ scope, boundary_id ]
    end
  end

  def default_cdef_boundary_id
    writable = CdefWriteAccess.writable_boundary_ids(current_user)
    if action_name == "copy" && respond_to?(:cdef_write_target, true) && cdef_write_target
      source = CdefWriteAccess.boundary_id(cdef_write_target)
      return source if source && writable.include?(source)
    end
    writable.first if writable.size == 1
  end

  # Apply the requested scope to a CDEF this request created. Nothing to apply
  # when none was requested (an instance-level writer's unscoped create, as
  # before #1258). Raises ArgumentError on an unusable combination.
  def apply_requested_cdef_scope!(cdef)
    scope, boundary_id = requested_cdef_scope
    return if scope.nil?

    CdefScopeService.apply(cdef, scope: scope, authorization_boundary_id: boundary_id,
                                 organization_id: current_user&.organizations&.first&.id)
  end
end
