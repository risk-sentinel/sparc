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
    def boundary_scoped(model, read:, write:)
      class_attribute :bsd_model, :bsd_read_key, :bsd_write_key
      self.bsd_model = model
      self.bsd_read_key = read
      self.bsd_write_key = write
    end
  end

  private

  # Index scope: admin -> all; else records in the user's boundaries + globals (nil).
  def boundary_scoped_relation(relation)
    return relation unless SparcConfig.any_auth_enabled?
    return relation if current_user&.admin?

    boundary_ids = current_user ? current_user.authorization_boundaries.ids : []
    relation.where(authorization_boundary_id: boundary_ids + [ nil ])
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
    return if record.authorization_boundary_id.nil?    # global / instance-wide -> open to all

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
