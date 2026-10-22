# frozen_string_literal: true

# #1244 — who may do what to an authorization boundary, as ONE definition the
# web controller and Api::V1::AuthorizationBoundariesController both include.
#
#   read   authorization_boundaries.read  on the boundary (or instance-wide)
#   write  authorization_boundaries.write on the boundary (or instance-wide)
#   create authorization_boundaries.write, instance-level: a new boundary has no
#          boundary to hold a grant on yet
#
# Destroy is not here: it is instance-administrator only on both surfaces.
#
# Before this, the web controller checked nothing but bulk_destroy, and the API
# accepted only an instance-level write for update, refusing the boundary's own
# ISSO/ISSM, to whom wiki/RBAC.md delegates authorization_boundaries.write
# (owner, 2026-10-22: one rule, boundary-scoped).
#
# The including controller supplies `access_boundary`, the loaded boundary.
# `authorize_permission!` carries the administrator bypass, honours
# SparcConfig.any_auth_enabled? and audits each refusal.
#
# NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege).
module AuthorizationBoundaryAccess
  extend ActiveSupport::Concern

  READ_KEY  = AuthorizationBoundary::READ_PERMISSION
  WRITE_KEY = AuthorizationBoundary::WRITE_PERMISSION

  private

  def authorize_boundary_read!
    authorize_permission!(READ_KEY, authorization_boundary_id: access_boundary.id)
  end

  def authorize_boundary_write!
    authorize_permission!(WRITE_KEY, authorization_boundary_id: access_boundary.id)
  end

  def authorize_boundary_create!
    authorize_permission!(WRITE_KEY)
  end
end
