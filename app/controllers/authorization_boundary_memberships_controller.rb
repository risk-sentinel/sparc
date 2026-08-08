class AuthorizationBoundaryMembershipsController < ApplicationController
  # CRITICAL — this controller had NO authorization of any kind.
  #
  # `set_authorization_boundary` is an unscoped `find_by!(slug:)`, and
  # ApplicationController enforces only AUTHENTICATION (session, password,
  # WebAuthn, auth method). Nothing checked whether the signed-in user had any
  # relationship to the boundary whose roster they were editing.
  #
  # Demonstrated before the fix: a non-admin, non-member user POSTed to
  # `/authorization_boundaries/:slug/memberships` and got
  # `302 / "Member 'Victim' added as Assessor / 3PAO."` — a role granted on a
  # boundary they had nothing to do with. Boundary roles gate access to
  # compliance documents, so that is privilege escalation (OWASP A01), not just
  # an untidy roster.
  #
  # The Api::V1 equivalent was already gated with `authorize_boundary_write!`;
  # only the web path was open. This mirrors that policy exactly — the same
  # permission key, with the admin bypass that `User#has_permission?` provides —
  # so the two surfaces cannot drift into disagreeing about who may edit a
  # roster.
  #
  # NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege),
  # AC-2 (account management — role assignment).
  before_action :set_authorization_boundary
  before_action :authorize_boundary_write!
  before_action :set_membership, only: [ :edit, :update, :destroy ]

  def new
    @membership = @authorization_boundary.authorization_boundary_memberships.new
    load_roster
  end

  def create
    @membership = @authorization_boundary.authorization_boundary_memberships.new(membership_params)

    if @membership.save
      audit_log("authorization_boundary_membership_created", subject: @membership, metadata: { authorization_boundary_id: @authorization_boundary.id, user_name: @membership.user_name })
      flash[:success] = "Member '#{@membership.user_name}' added as #{@membership.role_label}."
      # #869 — stay in the add loop. Building a roster is inherently repetitive;
      # bouncing back to the boundary after every save meant re-opening the form
      # for each person, with no view of who was already on it. Leaving is now an
      # intentional act (Done / Cancel), not the default.
      redirect_to new_authorization_boundary_membership_path(@authorization_boundary)
    else
      flash.now[:error] = @membership.errors.full_messages.join(", ")
      load_roster
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  # #869 — edit deliberately still returns to the boundary. Correcting one
  # person's role is a single errand, not a loop: there is nothing to add next,
  # so keeping the operator on a form for a record they just finished editing
  # would strand them. Only `create` repeats.
  def update
    if @membership.update(membership_params)
      audit_log("authorization_boundary_membership_updated", subject: @membership, metadata: { authorization_boundary_id: @authorization_boundary.id })
      flash[:success] = "Membership updated."
      redirect_to @authorization_boundary
    else
      flash.now[:error] = @membership.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    audit_log("authorization_boundary_membership_deleted", subject: @membership, metadata: { authorization_boundary_id: @authorization_boundary.id })
    @membership.destroy
    flash[:success] = "Member removed."
    redirect_to @authorization_boundary
  end

  private

  def set_authorization_boundary
    @authorization_boundary = AuthorizationBoundary.find_by!(slug: params[:authorization_boundary_id])
  end

  # Same key and same shape as Api::V1::AuthorizationBoundaryMembershipsController.
  # `has_permission?` returns true for instance admins, so the admin bypass the
  # API spells out explicitly is preserved here without duplicating it.
  def authorize_boundary_write!
    authorize_permission!("authorization_boundaries.write")
  end

  def set_membership
    @membership = @authorization_boundary.authorization_boundary_memberships.find(params[:id])
  end

  # #869 — the same unified roster the boundary screen shows (#770 bug 3), so
  # the operator can see progress and spot duplicates without leaving the form.
  def load_roster
    @personnel = @authorization_boundary.personnel_roster
  end

  # #875 — permit the role and let the model decide. The old hand-rolled
  # allowlist checked against the DISPLAY list while the enum enforced its own
  # keys, and the two disagreed: a configured label passed the check and then
  # raised ArgumentError inside the enum — the 500 this issue reports. It also
  # dropped an unrecognised value silently, so the operator was told "Role can't
  # be blank" about a role they had plainly selected. The model now resolves and
  # validates in one place, and says which part is wrong.
  def membership_params
    params.require(:authorization_boundary_membership).permit(:user_name, :user_email, :role)
  end
end
