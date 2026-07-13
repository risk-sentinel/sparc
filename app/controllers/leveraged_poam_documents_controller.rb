# Read-only view of POA&M documents owned by leveraged-system boundaries
# (#415 Scenario A — same-instance).
#
# A leveraging boundary that consumes a leveraged authorization (#396)
# inherits the leveraged system's risk posture; the leveraging system's
# AOs need visibility into the open POA&M items behind that inheritance
# to demonstrate informed reliance during their own ATO review.
#
# This controller surfaces those POA&Ms read-only — every write action
# is intentionally absent. Existing permission gates on
# `PoamDocumentsController` already prevent leveraging-side users from
# mutating the leveraged POA&M (they don't hold poam.write on the
# leveraged boundary), so this controller's scope is purely the
# read-only browse + show surface.
#
# Cross-instance / federated visibility (Scenario B) is tracked in #422.
#
# NIST 800-53:
#   AC-3 / AC-21 — read-only access enforcement; cross-boundary info sharing
#   AU-2 — every cross-boundary view emits an AuditEvent so the
#         leveraged system has visibility into who is consuming its data
class LeveragedPoamDocumentsController < ApplicationController
  before_action :set_poam_document, only: :show

  def index
    @leveraged_poams = visible_leveraged_poam_documents.includes(:authorization_boundary).distinct
  end

  def show
    audit_log("poam_document_viewed_by_leveraging_user", subject: @poam_document,
              metadata: { leveraged_boundary: @poam_document.authorization_boundary&.name,
                          leveraging_user_id: current_user.id })
    @poam_items = @poam_document.poam_items.order(:row_order, :id)
    @poam_risks = @poam_document.poam_risks.order(:title)
    @poam_observations = @poam_document.poam_observations.order(:title)
    @poam_findings = @poam_document.poam_findings.order(:title)
  end

  private

  # Boundaries the current user accesses *as a leveraging participant* —
  # i.e., the leveraged_boundary side of any LeveragedAuthorization where
  # the leveraging_boundary is one the user can see.
  def visible_leveraged_poam_documents
    leveraged_boundary_ids = LeveragedAuthorization
                               .where(leveraging_boundary_id: accessible_boundary_ids)
                               .pluck(:leveraged_boundary_id)
                               .compact
    PoamDocument.where(authorization_boundary_id: leveraged_boundary_ids)
                .where(deleted_at: nil)
  end

  def accessible_boundary_ids
    # Conservatively scope to all boundaries the user has any role on.
    # Falls back to instance-admin = all boundaries.
    return AuthorizationBoundary.ids if current_user.admin?

    UserRole.where(user_id: current_user.id)
            .where.not(authorization_boundary_id: nil)
            .pluck(:authorization_boundary_id).uniq
  end

  def set_poam_document
    @poam_document = visible_leveraged_poam_documents.find_by!(slug: params[:id])
  end
end
