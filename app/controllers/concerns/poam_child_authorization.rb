# frozen_string_literal: true

# #919 — authorization for the POA&M child controllers (findings, items, local
# components, milestones, observations, remediations, risks).
#
# All seven shipped with no authorization of any kind. The natural assumption is
# that nesting under a POA&M document scopes them, but it does not: every one of
# them loads its parent with an UNSCOPED lookup and only then scopes children to
# it —
#
#     @poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])
#     @poam_risk     = @poam_document.poam_risks.find(params[:id])
#
# — which buys referential integrity, not access control. Knowing a POA&M's slug
# was sufficient to rewrite its findings, milestones and remediation dates: the
# figures an AO relies on when accepting residual risk.
#
# The permission keys and the boundary scoping mirror
# Api::V1::PoamRisksController, which was already correct, so the two surfaces
# cannot drift. Scoping is on the PARENT document's boundary, matching the API's
# `@boundary = @document.authorization_boundary`.
#
# `authorize_permission!` (not a hand-rolled check) is deliberate: it carries the
# admin bypass, honours `SparcConfig.any_auth_enabled?`, and emits the
# `authorization_failure` audit event. A bespoke guard silently loses all three —
# see `leveraged_authorizations`, which did exactly that.
#
# NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege),
# AU-2 (auditable events).
module PoamChildAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_poam_read!
    authorize_permission!("poam.read", authorization_boundary_id: poam_authorization_boundary_id)
  end

  def authorize_poam_write!
    authorize_permission!("poam.write", authorization_boundary_id: poam_authorization_boundary_id)
  end

  # Nil when the parent has no boundary — `authorize_permission!` then requires
  # an instance-level grant, which is the correct fail-closed direction: an
  # unassociated document must not be editable by anyone holding the permission
  # on some unrelated boundary.
  def poam_authorization_boundary_id
    @poam_document&.authorization_boundary_id
  end
end
