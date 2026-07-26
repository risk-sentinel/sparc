# frozen_string_literal: true

# #447 — HDF scan ingest, nested under an AuthorizationBoundary.
#
#   GET    /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs
#   GET    /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs/:id  (uuid)
#   POST   /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs
#
# Ingest accepts either a multipart upload (`file`) or a raw HDF JSON body.
# Boundary-scoped RBAC reuses the evidence.read/write permissions — scan findings
# are boundary-scoped assessment material, and the AO-signoff requirements for
# risk-accepting dispositions live in the disposition service, not in RBAC.
#
# NIST 800-53: IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC),
# CA-7/RA-5 (continuous monitoring / vuln scanning), AU-12 (audit), SI-10 (input validation).
class Api::V1::ScanRunsController < Api::V1::BaseController
  before_action :set_boundary
  before_action :authorize_read!,  only: %i[index show]
  before_action :authorize_write!, only: %i[create]

  # GET .../scan_runs
  def index
    result = paginate(@boundary.scan_runs.recent)
    render json: { data: result[:data].map { |r| serialize(r) }, meta: result[:meta] }
  end

  # GET .../scan_runs/:id  (uuid)
  def show
    run = @boundary.scan_runs.find_by!(uuid: params[:id])
    render json: { data: serialize(run, detailed: true) }
  end

  # POST .../scan_runs
  def create
    run = HdfIngestService.new(@boundary).ingest(
      read_upload,
      source_filename: @source_filename,
      created_by: current_user&.display_name.presence || current_user&.email
    )
    audit_log("scan_run_ingested", subject: run,
              metadata: { scanner: run.scanner, findings: run.finding_count, failed: run.failed_count })
    render json: { data: serialize(run, detailed: true) }, status: :created
  rescue HdfIngestService::IngestError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_boundary
    key = params[:authorization_boundary_id]
    @boundary =
      if key.to_s.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  # Multipart `file` param, else the raw request body. `raw_post` is memoized by
  # Rack and survives JSON param-parsing, unlike `request.body.read`.
  def read_upload
    upload = params[:file] || params.dig(:scan_run, :file)
    if upload.respond_to?(:read)
      @source_filename = upload.original_filename if upload.respond_to?(:original_filename)
      upload.read
    else
      request.raw_post
    end
  end

  def serialize(run, detailed: false)
    data = {
      id: run.id,
      uuid: run.uuid,
      scanner: run.scanner,
      scanner_version: run.scanner_version,
      authorization_boundary_id: run.authorization_boundary_id,
      ingested_at: run.ingested_at&.utc&.iso8601,
      finding_count: run.finding_count,
      passed_count: run.passed_count,
      failed_count: run.failed_count,
      skipped_count: run.skipped_count,
      created_at: run.created_at.utc.iso8601
    }
    if detailed
      data[:source_filename] = run.source_filename
      data[:raw_hdf_digest] = run.raw_hdf_digest
      data[:created_by] = run.created_by
    end
    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view scan runs"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.write", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to ingest scans"
  end
end
