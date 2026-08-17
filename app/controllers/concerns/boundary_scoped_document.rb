# frozen_string_literal: true

# Boundary-scoped access control for the document *web* controllers
# (Evidence, SSP, SAR, SAP, POA&M). Mirrors the Api::V1::DocumentBaseController
# pattern so the web UI enforces the same rules as the API (#738).
#
# Model requirement: the document class has an optional `authorization_boundary_id`.
#
# Rules (all no-ops when no auth method is enabled — backward compatible):
#   - index/collection: Instance-Admin sees all; other users see records in the
#     boundaries they have any role on PLUS "global" records (nil boundary).
#   - read of a specific record: global (nil-boundary) records are open to any
#     authenticated user; boundary records require the `<type>.read` permission
#     on that boundary.
#   - write: require the `<type>.write` permission on the record's boundary
#     (or the boundary from params for create); global records require the
#     permission at instance level.
#
# Controllers opt in with:
#   include BoundaryScopedDocument
#   boundary_scoped SspDocument, read: "ssp.read", write: "ssp.write"
# then wire the before_actions with the action lists:
#   before_action :authorize_document_read!,  only: [ :show, :edit, :download_json, ... ]
#   before_action :authorize_document_write!, only: [ :create, :update, :destroy, ... ]
# and scope the index:
#   @ssp_documents = boundary_scoped_relation(SspDocument).order(created_at: :desc)
#
# NIST 800-53: AC-3 Access Enforcement.
module BoundaryScopedDocument
  extend ActiveSupport::Concern

  class_methods do
    # `global_fallback:` — whether a record with a NIL boundary is treated as
    # instance-wide and shown to every signed-in user (#952).
    #
    # True for Evidence, which is leveraged and inherited across boundaries, so
    # a boundary-less evidence record is a legitimate instance-wide thing.
    #
    # False for SSP/SAP/SAR/POA&M, which are per-system by definition. Those
    # types now require a boundary, but rows written before that rule exist on
    # every upgraded instance, and until they are repaired the old fallback
    # would keep showing each one to everybody. Turning it off per model closes
    # that without changing the rule for Evidence — the fallback itself is
    # correct, it was just being applied to types that can never be global.
    def boundary_scoped(model, read:, write:, global_fallback: true)
      class_attribute :bsd_model, :bsd_read_key, :bsd_write_key, :bsd_global_fallback
      self.bsd_model = model
      self.bsd_read_key = read
      self.bsd_write_key = write
      self.bsd_global_fallback = global_fallback
    end
  end

  private

  # Index scope: admin -> all; else records in the user's boundaries, plus
  # globals (nil) only for a type that can legitimately BE global (#952).
  def boundary_scoped_relation(relation)
    return relation unless SparcConfig.any_auth_enabled?
    return relation if current_user&.admin?

    boundary_ids = current_user ? current_user.authorization_boundaries.ids : []
    boundary_ids += [ nil ] if bsd_global_fallback
    relation.where(authorization_boundary_id: boundary_ids)
  end

  # The loaded record for a member action (e.g. @ssp_document), by naming convention.
  def bsd_document_record
    instance_variable_get("@#{bsd_model.model_name.param_key}")
  end

  # before_action for read (member) actions.
  def authorize_document_read!
    return unless SparcConfig.any_auth_enabled?

    record = bsd_document_record
    return if record.nil?                              # collection action / not loaded

    if record.authorization_boundary_id.nil?
      # #952 — "no boundary means instance-wide, open to all" is right for
      # Evidence and wrong for the per-system types, where it meant a legacy
      # orphan was readable by every signed-in user. Those fall through to an
      # instance-level permission check instead, which an Instance-Admin holds
      # and an ordinary member does not.
      return if bsd_global_fallback

      return authorize_permission!(bsd_read_key)
    end

    authorize_permission!(bsd_read_key, authorization_boundary_id: record.authorization_boundary_id)
  end

  # before_action for write actions (member or collection/create).
  #
  # #929 — a write that MOVES a document must be authorized against the target
  # boundary too. This previously read `record&.authorization_boundary_id ||
  # params[…]`, so once a record had a boundary the requested one was never
  # looked at, and a user with write on boundary A could move a document into
  # boundary B without holding anything on B.
  def authorize_document_write!
    return unless SparcConfig.any_auth_enabled?

    record = bsd_document_record
    current_id   = record&.authorization_boundary_id
    requested_id = requested_boundary_id

    # Create (no record) authorizes the requested boundary; attaching an orphan
    # likewise authorizes the target, since `current_id` is nil.
    authorize_permission!(bsd_write_key, authorization_boundary_id: current_id || requested_id)

    # Re-pointing: hold write on the boundary it LEAVES and the one it JOINS.
    return if requested_id.blank? || current_id.blank?
    return if requested_id.to_s == current_id.to_s

    authorize_permission!(bsd_write_key, authorization_boundary_id: requested_id)
  end

  # The boundary this request is asking the document to belong to.
  #
  # The top-level `authorization_boundary_id` is honoured ONLY for the attach
  # action. Index and filter screens carry that same param name to narrow a
  # list, and letting it reach an authorization decision would mean a query
  # string chose which boundary was checked.
  def requested_boundary_id
    nested = params.dig(bsd_model.model_name.param_key, :authorization_boundary_id).presence
    return nested if nested.present?

    params[:authorization_boundary_id].presence if action_name == "attach_boundary"
  end
end
