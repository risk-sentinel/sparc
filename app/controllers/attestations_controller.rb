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
      redirect_to evidence_path(@evidence), notice: "Attestation recorded by #{@attestation.attester_name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    attestation = @evidence.attestations.find(params[:id])
    attestation.destroy
    redirect_to evidence_path(@evidence), notice: "Attestation removed."
  end

  private

  def set_evidence
    @evidence = Evidence.find(params[:evidence_id])
  end

  def attestation_params
    params.require(:attestation).permit(:attester_name, :attester_email, :role, :statement, :attested_at)
  end
end
