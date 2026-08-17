# frozen_string_literal: true

# Attach a document to an authorization boundary AFTER upload (#929).
#
# The boundary could be set at creation and never again: every web controller
# omitted `authorization_boundary_id` from `document_metadata_params` while
# `Api::V1` permitted it all along, so an operator whose upload did not
# associate could only recover by calling the API by hand. That is the
# thin-client rule backwards, and the second confirmed instance of it after
# #928.
#
# One action serves both entry points — the document's own screen and the
# boundary's "Add…" tile — so there is no parallel implementation to drift.
#
# Requires the including controller to have declared `boundary_scoped`
# (BoundaryScopedDocument), which supplies `bsd_model` and the loaded record.
#
# Lifecycle rule:
#   - A document with NO boundary can be attached at any lifecycle state. This
#     is the recovery case #929 was raised for, and a published orphan is
#     exactly the document most in need of repair.
#   - Re-pointing a document that already has a boundary requires a draft, the
#     same bar every other metadata edit clears.
#
# Authorization is NOT performed here. The `authorize_document_write!`
# before_action covers this action and checks the TARGET boundary as well as
# the current one (see BoundaryScopedDocument).
#
# NIST 800-53: AC-3 Access Enforcement, AU-12 Audit Record Generation.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module BoundaryAttachable
  extend ActiveSupport::Concern

  # PATCH /<documents>/:id/attach_boundary
  def attach_boundary
    document = bsd_document_record
    target_id = attach_boundary_target_id

    if target_id.blank?
      return attach_boundary_failure(document, "Select an authorization boundary to attach this document to.")
    end

    if document.authorization_boundary_id.present? && !document.draft?
      return attach_boundary_failure(document,
        "This document is published and already belongs to a boundary. Create a copy to move it.")
    end

    target = AuthorizationBoundary.find_by(id: target_id)
    return attach_boundary_failure(document, "That authorization boundary no longer exists.") if target.nil?

    previous_id = document.authorization_boundary_id
    if document.update(authorization_boundary_id: target.id)
      audit_log("#{bsd_model.name.underscore}_boundary_attached", subject: document,
        metadata: { name: document.name,
                    authorization_boundary_id: target.id,
                    previous_authorization_boundary_id: previous_id })
      flash[:success] = "#{document.name} is now part of #{target.name}."
      redirect_to attach_boundary_redirect_path(document, target)
    else
      attach_boundary_failure(document, document.errors.full_messages.join(", "))
    end
  end

  private

  # Accepts the id nested under the document's param key (the document screen's
  # form, which shares shared/_boundary_picker) or at the top level (the
  # boundary attach screen, which posts one document at a time).
  def attach_boundary_target_id
    params.dig(bsd_model.model_name.param_key, :authorization_boundary_id).presence ||
      params[:authorization_boundary_id].presence
  end

  # Back to whichever screen sent us. `return_to` selects a route by name — it
  # is never used as a URL, so it cannot become an open redirect.
  def attach_boundary_redirect_path(document, target)
    return authorization_boundary_path(target) if params[:return_to] == "boundary"

    polymorphic_path(document)
  end

  def attach_boundary_failure(document, message)
    flash[:error] = message
    redirect_to polymorphic_path(document)
  end
end
