# Orchestrates creation of a complete ATO Authorization Package by creating
# or linking documents (Profile, CDEFs, SSP, SAP, SAR, POA&M) to an
# Authorization Boundary.
#
# Each step checks a mode parameter:
#   "select_existing" → find and link the document to the boundary
#   "create_new"      → delegate to existing service, then link
#   "skip"            → no action
#
# Usage:
#   service = AtoPackageService.new(authorization_boundary, params)
#   service.create  # => authorization_boundary (with linked documents)
#
class AtoPackageService
  def initialize(authorization_boundary, params)
    @ab = authorization_boundary
    @params = params.to_h.with_indifferent_access
  end

  def create
    ActiveRecord::Base.transaction do
      resolve_profile
      resolve_cdefs
      resolve_ssp
      resolve_sap
      resolve_sar
      resolve_poam
    end
    @ab
  end

  private

  # ── Step 1: Profile (select only — profiles must pre-exist) ────

  def resolve_profile
    return if @params[:profile_mode] == "skip" || @params[:profile_document_id].blank?

    @profile = ProfileDocument.find(@params[:profile_document_id])
  end

  # ── Step 2: Components (CDEFs) ─────────────────────────────────

  def resolve_cdefs
    return if @params[:cdef_mode] == "skip"

    ids = Array(@params[:cdef_document_ids]).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    # Ensure the AB has at least one boundary (environment) to link CDEFs through
    boundary = @ab.boundaries.first || @ab.boundaries.create!(
      name: "Default", environment: "production"
    )

    ids.each do |cdef_id|
      cdef = CdefDocument.find(cdef_id)
      boundary.boundary_cdef_documents.find_or_create_by!(cdef_document: cdef)
    end
  end

  # ── Step 3: SSP ────────────────────────────────────────────────

  def resolve_ssp
    case @params[:ssp_mode]
    when "select_existing"
      @ssp = SspDocument.find(@params[:ssp_document_id])
      @ssp.update!(authorization_boundary: @ab)
    when "create_new"
      wizard_params = {
        name: @params[:ssp_name].presence || "SSP for #{@ab.name}",
        description: @params[:ssp_description],
        profile_document_id: @profile&.id,
        system_status: @params[:system_status],
        security_sensitivity_level: @params[:security_sensitivity_level],
        security_objective_confidentiality: @params[:security_objective_confidentiality],
        security_objective_integrity: @params[:security_objective_integrity],
        security_objective_availability: @params[:security_objective_availability],
        authorization_boundary_description: @params[:authorization_boundary_description]
      }
      wizard_params[:cdef_document_ids] = Array(@params[:cdef_document_ids]) if @params[:cdef_document_ids].present?

      @ssp = SspWizardService.new(wizard_params.with_indifferent_access).create
      @ssp.update!(authorization_boundary: @ab)
    end
  end

  # ── Step 4: SAP ────────────────────────────────────────────────

  def resolve_sap
    case @params[:sap_mode]
    when "select_existing"
      @sap = SapDocument.find(@params[:sap_document_id])
      @sap.update!(authorization_boundary: @ab)
    when "create_new"
      @sap = SapGeneratorService.new(
        name: @params[:sap_name].presence || "SAP for #{@ab.name}",
        ssp_document: @ssp,
        profile_document: @profile,
        assessment_type: @params[:assessment_type].presence || "initial",
        assessment_start: parse_date(@params[:assessment_start]),
        assessment_end: parse_date(@params[:assessment_end]),
        description: @params[:sap_description]
      ).generate
      @sap.update!(authorization_boundary: @ab)
    end
  end

  # ── Step 5: SAR ────────────────────────────────────────────────

  def resolve_sar
    case @params[:sar_mode]
    when "select_existing"
      @sar = SarDocument.find(@params[:sar_document_id])
      @sar.update!(authorization_boundary: @ab)
    when "create_new"
      sar_params = {
        name: @params[:sar_name].presence || "SAR for #{@ab.name}",
        description: @params[:sar_description],
        sap_document_id: @sap&.id,
        assessment_start: @params[:sar_assessment_start],
        assessment_end: @params[:sar_assessment_end]
      }
      @sar = SarWizardService.new(sar_params).create
      @sar.update!(authorization_boundary: @ab)
    end
  end

  # ── Step 6: POA&M ──────────────────────────────────────────────

  def resolve_poam
    case @params[:poam_mode]
    when "select_existing"
      @poam = PoamDocument.find(@params[:poam_document_id])
      @poam.update!(authorization_boundary: @ab)
    when "create_new"
      @poam = PoamDocument.create!(
        name: @params[:poam_name].presence || "POA&M for #{@ab.name}",
        description: @params[:poam_description],
        status: "completed",
        lifecycle_status: "started",
        authorization_boundary: @ab
      )
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end
end
