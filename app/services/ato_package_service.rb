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
#   service = AtoPackageService.new(authorization_boundary, params, existing_scope: ->(klass) { ... })
#   service.create  # => authorization_boundary (with linked documents)
#
# #1244 — "select_existing" looks the SSP/SAP/SAR/POA&M up inside
# `existing_scope`, never across the instance. It used to `find` any document
# by id and re-point it here, so a caller allowed to build one boundary's
# package could pull another boundary's documents into it. The default scope is
# this boundary's own documents; the controller widens it only to the
# boundary-less documents its caller may attach.
#
class AtoPackageService
  # #843 — source risks the POA&M step could not convert, with the reason for
  # each. Empty unless the SAR carried risks missing required OSCAL content.
  # Public because it is the only channel by which a caller learns that the
  # generated POA&M is thinner than the assessment justified.
  attr_reader :poam_skipped

  def initialize(authorization_boundary, params, existing_scope: nil)
    @ab = authorization_boundary
    @existing_scope = existing_scope || ->(klass) { klass.where(authorization_boundary_id: authorization_boundary.id) }
    @params = params.to_h.with_indifferent_access
    @poam_skipped = []
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

  # #1101 — a boundary's baseline, once set, is settled: it is the one this
  # package uses, whatever the request names. A boundary with none takes the
  # one chosen here as its baseline; before, the choice fed this one package
  # and was thrown away, so the next run asked again. Only a published baseline
  # with a resolved catalog can be chosen (ProfileDocument.ssp_ready), the same
  # set the wizard offers.
  def resolve_profile
    if (settled = @ab.profile_document)
      @profile = settled
      return
    end
    return if @params[:profile_mode] == "skip" || @params[:profile_document_id].blank?

    @profile = ProfileDocument.ssp_ready.find(@params[:profile_document_id])
    @ab.update!(profile_document: @profile)
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
      @ssp = existing(SspDocument, :ssp, "an SSP")
      @ssp.update!(authorization_boundary: @ab)
    when "create_new"
      wizard_params = {
        name: @params[:ssp_name].presence || "SSP for #{@ab.name}",
        description: @params[:ssp_description],
        # #1101 — an SSP belongs to its boundary from creation (#952); creating
        # it boundary-less and moving it in afterwards failed every time.
        authorization_boundary_id: @ab.id,
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
    else
      nil # no/unknown ssp_mode: skip this step
    end
  end

  # ── Step 4: SAP ────────────────────────────────────────────────

  def resolve_sap
    case @params[:sap_mode]
    when "select_existing"
      @sap = existing(SapDocument, :sap, "a SAP")
      @sap.update!(authorization_boundary: @ab)
    when "create_new"
      @sap = SapGeneratorService.new(
        name: @params[:sap_name].presence || "SAP for #{@ab.name}",
        ssp_document: @ssp,
        profile_document: @profile,
        assessment_type: @params[:assessment_type].presence || "initial",
        assessment_start: parse_date(@params[:assessment_start]),
        assessment_end: parse_date(@params[:assessment_end]),
        description: @params[:sap_description],
        authorization_boundary: @ab   # #952 — required at creation now
      ).generate
    else
      nil # no/unknown sap_mode: skip this step
    end
  end

  # ── Step 5: SAR ────────────────────────────────────────────────

  def resolve_sar
    case @params[:sar_mode]
    when "select_existing"
      @sar = existing(SarDocument, :sar, "a SAR")
      @sar.update!(authorization_boundary: @ab)
    when "create_new"
      sar_params = {
        name: @params[:sar_name].presence || "SAR for #{@ab.name}",
        description: @params[:sar_description],
        authorization_boundary_id: @ab.id, # #1101, as for the SSP above
        sap_document_id: @sap&.id,
        assessment_start: @params[:sar_assessment_start],
        assessment_end: @params[:sar_assessment_end]
      }
      @sar = SarWizardService.new(sar_params).create
      @sar.update!(authorization_boundary: @ab)
    else
      nil # no/unknown sar_mode: skip this step
    end
  end

  # ── Step 6: POA&M ──────────────────────────────────────────────

  def resolve_poam
    case @params[:poam_mode]
    when "select_existing"
      @poam = existing(PoamDocument, :poam, "a POA&M")
      @poam.update!(authorization_boundary: @ab)
    when "create_new"
      # #843 — POA&M used to be the one step in this wizard that produced an
      # EMPTY shell while every other step produced a populated document. When
      # the wizard has just built a SAR, its open risks are exactly the
      # remediation work the POA&M exists to track, so they are carried across.
      #
      # With no SAR (the step was skipped, or an existing POA&M route was not
      # taken) this still yields an empty document — a team starting a POA&M
      # before a full assessment is a legitimate flow, not a failure.
      generation = PoamGeneratorService.new(
        name: @params[:poam_name].presence || "POA&M for #{@ab.name}",
        description: @params[:poam_description],
        sar_document: @sar,
        authorization_boundary: @ab
      ).generate

      @poam = generation.poam_document
      # Surfaced rather than swallowed: a risk the assessment recorded but the
      # POA&M could not carry is exactly what an author needs to know about.
      @poam_skipped = generation.skipped
      @poam
    else
      nil # no/unknown poam_mode: skip this step
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  # #1101 — a step can start on "select existing" with nothing chosen (the
  # boundary has several and the author picks); submitted that way, say so
  # rather than "Couldn't find SspDocument without an ID".
  def existing(klass, step, noun)
    id = @params[:"#{step}_document_id"]
    raise ArgumentError, "choose #{noun} to use, or skip that step" if id.blank?

    @existing_scope.call(klass).find(id)
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end
end
