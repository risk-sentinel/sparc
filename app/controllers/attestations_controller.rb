class AttestationsController < ApplicationController
  before_action :set_evidence

  def new
    @attestation = @evidence.attestations.build(attested_at: Time.current)
  end

  def create
    @attestation = @evidence.attestations.build(attestation_params)

    if @attestation.save
      @attestation.generate_signature!
      @evidence.update!(status: :attested) unless @evidence.attested?
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

  def set_evidence
    @evidence = Evidence.find_by!(slug: params[:evidence_id])
  end

  def attestation_params
    params.require(:attestation).permit(:attester_name, :attester_email, :role, :statement, :attested_at, :frequency, :status)
  end
end
