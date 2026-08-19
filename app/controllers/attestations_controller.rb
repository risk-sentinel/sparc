class AttestationsController < ApplicationController
  before_action :set_evidence
  # #919 — attesting to evidence, or retracting an attestation, is a write on
  # the assessor trail. This controller had no guard and loaded @evidence with an
  # unscoped find_by!(slug:), so any signed-in user who knew a slug could attest.
  #
  # Scoped to the evidence's boundary, matching how EvidencesController protects
  # evidence itself (boundary_scoped Evidence, write: "evidence.write"). NOTE this
  # is deliberately STRICTER than Api::V1::AttestationsController, whose check is
  # unscoped — being stricter than the sibling is the safe direction, but the two
  # should be reconciled; tracked in the #919 memo.
  before_action :authorize_attestation_write!

  def new
    @attestation = @evidence.attestations.build(attested_at: Time.current)
  end

  def create
    @attestation = @evidence.attestations.build(attestation_params)

    if @attestation.save
      @attestation.generate_signature!
      # #947 — check the STATUS, not `attested?`.
      #
      # `Evidence#attested?` is explicitly defined as `attestations.any?`, which
      # SHADOWS the predicate the `status` enum generates for the "attested"
      # value. By the time this line runs the attestation has just been saved, so
      # the shadowing method is always true and the status update never fired —
      # evidence could be signed off and still read "Draft" everywhere. The old
      # spec asserted the status was one of four values, which no outcome could
      # fail, so nothing caught it.
      @evidence.update!(status: :attested) unless @evidence.status == "attested"
      audit_log("attestation_created", subject: @attestation, metadata: { evidence_id: @evidence.id })
      redirect_to evidence_path(@evidence), notice: "Attestation recorded by #{@attestation.attester_name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    attestation = @evidence.attestations.find(params[:id])
    audit_log("attestation_deleted", subject: attestation, metadata: { evidence_id: @evidence.id })
    attestation.destroy
    redirect_to evidence_path(@evidence), notice: "Attestation removed."
  end

  private

  def authorize_attestation_write!
    authorize_permission!("evidence.write",
                          authorization_boundary_id: @evidence&.authorization_boundary_id)
  end

  def set_evidence
    @evidence = Evidence.find_by!(slug: params[:evidence_id])
  end

  # #947 — `attester_name` / `attester_email` are NOT permitted. They are the
  # snapshot the model takes from the resolved account (#934 rule), not values a
  # user types. Permitting them would put the free-text field this issue removed
  # straight back, and let a request name one person while referencing another.
  def attestation_params
    params.require(:attestation).permit(:attester_user_id, :role, :statement, :attested_at, :frequency, :status)
  end
end
