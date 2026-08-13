# frozen_string_literal: true

# REST API for Terraform → CDEF coverage analysis (#904).
#
# Answers "what CDEFs does this boundary need?" from the infrastructure the
# boundary actually declares, instead of somebody reading Terraform by eye.
#
# Endpoints:
#   POST   /api/v1/cdef_coverage/analyze   — multipart, N files, returns a report
#   POST   /api/v1/cdef_coverage/runs      — save a report against a boundary
#   GET    /api/v1/cdef_coverage/runs      — saved runs (boundary-scoped)
#   GET    /api/v1/cdef_coverage/runs/:id  — one saved run
#   DELETE /api/v1/cdef_coverage/runs/:id  — remove a saved run
#
# ── Analysing does not persist ────────────────────────────────────────────
#
# `analyze` reads the uploads, answers, and keeps nothing. Saving is a separate
# call, so an operator can assess a boundary — including one that does not exist
# yet, from a plan — without committing anything. It is also why `analyze`
# requires only read permission: it writes nothing.
#
# ── The uploads are never stored ──────────────────────────────────────────
#
# A .tfstate carries plaintext secrets. Files are parsed from the request and
# discarded; nothing is attached to a record and no Active Storage blob is
# created. What can be persisted is the derived census — service keys, resource
# TYPE names, counts, verdicts — plus each file's name and SHA-256.
#
# NIST 800-53 Controls:
#   IA-2  Identification and Authentication (Bearer token required)
#   AC-3  Access Enforcement (cdef.read to analyse, cdef.write to save)
#   AC-6  Least Privilege (saved runs are boundary-scoped for non-admins)
#   AU-12 Audit Record Generation (analysis and save are logged)
#   CM-8  System Component Inventory (the inventory this derives)
#   SI-12 Information Management and Retention (uploads are not retained)
class Api::V1::CdefCoverageController < Api::V1::BaseController
  before_action :authorize_analyze!, only: %i[analyze]
  before_action :authorize_read!, only: %i[runs show_run]
  before_action :authorize_save!, only: %i[create_run]
  before_action :set_run, only: %i[show_run destroy_run]

  # POST /api/v1/cdef_coverage/analyze
  def analyze
    inventory = TerraformUploadInventoryService.call(uploads: uploaded_files)
    report = CdefCoverageAnalysis.call(inventory: inventory)

    audit_log("cdef_coverage_analyzed", metadata: {
      files: inventory.sources.map(&:filename),
      services: report.findings.size,
      needs_custom: report.counts["needs_custom"]
    })

    render json: { data: report.to_h }
  rescue TerraformUploadInventoryService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/cdef_coverage/runs
  #
  # Re-analyses the uploads rather than trusting a client-supplied report: a
  # saved coverage run is a compliance artifact, and one assembled from a POST
  # body would assert whatever the caller wanted it to.
  def create_run
    boundary = resolve_boundary
    inventory = TerraformUploadInventoryService.call(uploads: uploaded_files)
    report = CdefCoverageAnalysis.call(inventory: inventory)

    run = CdefCoverageRun.persist!(report: report, actor: current_user, authorization_boundary: boundary)
    audit_log("cdef_coverage_run_saved", subject: run,
              metadata: { boundary: boundary&.id, services: run.cdef_coverage_results.count })

    render json: { data: serialize_run(run, detailed: true) }, status: :created
  rescue TerraformUploadInventoryService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/v1/cdef_coverage/runs
  def runs
    result = paginate(scoped_runs.recent)
    render json: { data: result[:data].map { |r| serialize_run(r) }, meta: result[:meta] }
  end

  # GET /api/v1/cdef_coverage/runs/:id
  def show_run
    render json: { data: serialize_run(@run, detailed: true) }
  end

  # DELETE /api/v1/cdef_coverage/runs/:id
  def destroy_run
    audit_log("cdef_coverage_run_deleted", subject: @run, metadata: { boundary: @run.authorization_boundary_id })
    @run.destroy
    render json: { data: { id: @run.id, deleted: true } }
  end

  private

  def uploaded_files
    files = params[:files]
    files = [ files ] unless files.is_a?(Array)
    files.compact_blank
  end

  # A run may be attached to a boundary the caller can write to, or to none.
  def resolve_boundary
    id = params[:authorization_boundary_id].presence
    return nil if id.nil?

    boundary = AuthorizationBoundary.find(id)
    unless current_user.admin? || current_user.has_permission?("cdef.write", authorization_boundary_id: boundary.id)
      raise NotAuthorizedError, "Not authorized to save coverage for this boundary"
    end

    boundary
  end

  # Mirrors the evidence index (#934): non-admins see their boundaries' runs
  # plus unattached ones, so the API never hides a record the UI would show.
  def scoped_runs
    return CdefCoverageRun.all if current_user.admin?

    CdefCoverageRun.where(authorization_boundary_id: current_user.authorization_boundaries.ids + [ nil ])
  end

  def set_run
    @run = scoped_runs.find_by(id: params[:id]) || scoped_runs.find_by!(uuid: params[:id])
  end

  def authorize_analyze!
    return if current_user.admin?
    return if current_user.has_permission?("cdef.read")

    raise NotAuthorizedError, "Not authorized to analyze CDEF coverage"
  end
  alias_method :authorize_read!, :authorize_analyze!

  def authorize_save!
    return if current_user.admin?
    return if current_user.has_permission?("cdef.write")

    raise NotAuthorizedError, "Not authorized to save a coverage run"
  end

  def serialize_run(run, detailed: false)
    data = {
      id: run.id,
      uuid: run.uuid,
      authorization_boundary_id: run.authorization_boundary_id,
      analyzed_at: run.analyzed_at.utc.iso8601,
      created_by: run.created_by,
      created_by_user_id: run.created_by_user_id,
      counts: run.counts,
      source_files: run.source_files
    }

    if detailed
      data[:findings] = run.cdef_coverage_results.order(:verdict, :service_key).map do |result|
        {
          service: result.service_key,
          verdict: result.verdict,
          verdict_label: result.verdict_label,
          inferred: result.inferred,
          resource_count: result.resource_count,
          resource_types: result.resource_types,
          cdef_documents: result.cdef_documents
        }
      end
      data[:unmapped_resource_types] = run.unmapped_resource_types
    end

    data
  end
end
