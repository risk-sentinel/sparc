# frozen_string_literal: true

# #1258 — who may write a component definition, as ONE definition the web
# controller, Api::V1::CdefDocumentsController and the screens all read.
#
# Every built-in role that holds `cdef.write` (System Owner/ISO, ISSM, Cloud
# Service Provider, Common Control Provider, ...) holds it on an authorization
# boundary, and every CDEF write checked it at instance level only, so those
# grants never applied. Owner decisions, 2026-10-24:
#
#   - `cdef.write` held at instance level (Policy Manager; an instance
#     administrator through has_permission?'s break-glass) writes any CDEF.
#   - A boundary-scoped grant writes a CDEF only when it is boundary-scoped and
#     the user holds `cdef.write` on ALL of its boundaries. A CDEF's boundaries
#     are the ones its SCOPE was set to, and CdefScopeService.apply_boundary
#     records exactly one, so "all" is that boundary. A link added to an
#     environment from the boundary form or the ATO wizard uses the CDEF; it
#     does not make it that boundary's to edit, and must not lock its owner out.
#   - Organization-wide, instance-wide and unassigned CDEFs are refused to a
#     boundary-only writer.
#   - Creating needs a boundary the user holds `cdef.write` on; a boundary-only
#     writer cannot widen scope: organization-wide needs instance-level
#     `cdef.write`, instance-wide stays CdefScopeService.may_scope_instance?.
#
# #1275 — approval follows the same boundary rule (owner, 2026-10-24).
# ISSM, ISSO and System Owner hold `cdef.approve` on a boundary, and approval
# checked it at instance level only, so no boundary approver could approve.
# A boundary grant approves the CDEFs scoped to that boundary; instance-level
# `cdef.approve` (Policy Manager) approves every one. Separation of duties and
# the break-glass exemption stay in DocumentApprovalService#can_approve?.
#
# NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege), AC-5
# (separation of duties, in the service).
module CdefWriteAccess
  KEY = "cdef.write"
  APPROVE_KEY = "cdef.approve"
  SCOPES = %w[boundary global instance].freeze

  extend self

  # Instance-level `cdef.write`: writes every CDEF, at every tier.
  def instance_writer?(user) = user.present? && user.has_permission?(KEY)

  # The boundary a CDEF's scope was set to; nil unless it is boundary-scoped.
  # (Older rows can carry both a recorded boundary and globally_available; the
  # tier wins, so such a CDEF stays instance-level.)
  def boundary_id(cdef)
    return nil if cdef.globally_available?

    CdefScopeService.current_boundary_id(cdef).presence&.to_i
  end

  def may_write?(user, cdef) = granted_on?(user, cdef, KEY)

  # #1275 — the approver's authority. Who may not approve their own
  # submission is DocumentApprovalService's rule, not this one.
  def may_approve?(user, cdef) = granted_on?(user, cdef, APPROVE_KEY)

  # Instance-level `cdef.approve`. Only these may publish over the API without
  # review (ApiPublicationGuard); a boundary approver submits and has another
  # approve (owner, 2026-10-24).
  def instance_approver?(user) = user.present? && user.has_permission?(APPROVE_KEY)

  # May create a CDEF scoped to this boundary.
  def may_create_in?(user, boundary_id)
    return false if user.blank?
    return true if instance_writer?(user)
    return false if boundary_id.blank? || !AuthorizationBoundary.exists?(id: boundary_id)

    user.has_permission?(KEY, authorization_boundary_id: boundary_id.to_i)
  end

  # May create a CDEF anywhere: the "new" buttons.
  def may_create?(user) = instance_writer?(user) || (user.present? && writable_boundary_ids(user).any?)

  # May give a CDEF this scope (create, copy, or a scope change's target).
  def may_scope?(user, scope, boundary_id = nil)
    case scope.to_s
    when "instance" then CdefScopeService.may_scope_instance?(user)
    when "global"   then instance_writer?(user)
    when "boundary" then may_create_in?(user, boundary_id)
    else false
    end
  end

  # Boundaries a boundary-only writer may create into. (An instance writer may
  # use any boundary; the picker lists those it already lists.)
  def writable_boundary_ids(user)
    return [] if user.blank?
    return AuthorizationBoundary.ids if user.instance_administrator?

    user.boundary_ids_granting(KEY)
  end

  def writable_boundaries(user) = AuthorizationBoundary.where(id: writable_boundary_ids(user)).order(:name)

  # The refusal a caller sees for a scope it may not choose.
  def scope_refusal(scope)
    case scope.to_s
    when "instance" then CdefScopeService::INSTANCE_SCOPE_REFUSAL
    when "global"   then "Making a component definition organization-wide needs cdef.write across the instance."
    when "boundary" then "You may create or move a component definition only into a boundary where you hold cdef.write."
    else "Choose a scope for the component definition: a boundary you hold cdef.write on."
    end
  end

  private

  # `key` held across the instance, or on the boundary this CDEF is scoped to.
  def granted_on?(user, cdef, key)
    return false if user.blank? || cdef.nil?
    return true if user.has_permission?(key)

    id = boundary_id(cdef)
    id.present? && user.has_permission?(key, authorization_boundary_id: id)
  end
end
