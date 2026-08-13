# frozen_string_literal: true

# #904 — the CDEF coverage wizard.
#
# Upload the Terraform a boundary is built from, and get back what CDEFs it
# needs: adopt upstream's, keep ours, author a missing one, or retire an unused
# one. Reachable from the authorization boundary screen (its primary home) and
# from the CDEF index.
#
# A thin client over the same services Api::V1::CdefCoverageController uses, so
# a facet cannot be added to one surface and quietly missed on the other.
#
# ── The upload is never stored ────────────────────────────────────────────
#
# A .tfstate carries plaintext secrets. Files are parsed in-request and dropped;
# the wizard renders the derived report and holds nothing. Saving to a boundary
# is an explicit second action, and even then only the census is written. See
# CreateCdefCoverageRuns for what that means at the schema level.
#
# NIST: AC-3 (cdef.read to analyse, cdef.write to save), AU-12 (both audited),
# CM-8 (the inventory this derives), SI-12 (uploads are not retained).
class CdefCoverageController < ApplicationController
  include Auditable
  include CollectionViewable

  before_action :authorize_analyze!, only: %i[new analyze]
  before_action :authorize_save!, only: %i[create]
  before_action :set_boundary

  # GET /cdef_coverage/new
  def new
    @boundaries = assignable_boundaries
  end

  # POST /cdef_coverage/analyze — render the report, persist nothing.
  def analyze
    @report = build_report
    @report_token = CdefCoverageReportToken.sign(@report.to_h)
    @boundaries = assignable_boundaries
    audit_log("cdef_coverage_analyzed", metadata: {
      files: @report.inventory.sources.map(&:filename),
      needs_custom: @report.counts["needs_custom"]
    })
    render :report
  rescue TerraformUploadInventoryService::Error => e
    @boundaries = assignable_boundaries
    flash.now[:error] = e.message
    render :new, status: :unprocessable_entity
  end

  # POST /cdef_coverage — save the analysis against a boundary.
  #
  # Saves from the signed token the report screen carried, not from re-uploaded
  # files: the upload was discarded during analysis, so asking for it again is a
  # cost the operator should not pay for a property they cannot see. The
  # signature is what makes the round trip trustworthy — a saved run is a
  # compliance artifact, and an unsigned payload would let a caller assert
  # whatever coverage they liked.
  def create
    hash = CdefCoverageReportToken.verify(params[:report_token])
    run = CdefCoverageRun.persist_report_hash!(hash: hash, actor: current_user,
                                               authorization_boundary: @boundary)
    audit_log("cdef_coverage_run_saved", subject: run, metadata: { boundary: @boundary&.id })

    redirect_to cdef_coverage_path(run),
                flash: { success: "Coverage analysis saved#{" to #{@boundary.name}" if @boundary}." }
  rescue CdefCoverageReportToken::Error => e
    @boundaries = assignable_boundaries
    flash.now[:error] = e.message
    render :new, status: :unprocessable_entity
  end

  # GET /cdef_coverage — saved runs.
  def index
    @runs = scoped_runs.recent.includes(:authorization_boundary)
    @pagy, @runs = paginate_collection(@runs)
  end

  # GET /cdef_coverage/:id
  def show
    @run = scoped_runs.find_by(id: params[:id]) || scoped_runs.find_by!(uuid: params[:id])
    @results = @run.cdef_coverage_results.order(:verdict, :service_key)
  end

  private

  def build_report
    inventory = TerraformUploadInventoryService.call(uploads: uploaded_files)
    CdefCoverageAnalysis.call(inventory: inventory)
  end

  def uploaded_files
    files = params[:files]
    files = [ files ] unless files.is_a?(Array)
    files.compact_blank
  end

  def set_boundary
    id = params[:authorization_boundary_id].presence
    @boundary = AuthorizationBoundary.find_by(id: id) if id
  end

  def assignable_boundaries
    return AuthorizationBoundary.order(:name) if current_user&.admin?

    current_user&.authorization_boundaries&.order(:name) || AuthorizationBoundary.none
  end

  def scoped_runs
    return CdefCoverageRun.all if current_user&.admin?

    CdefCoverageRun.where(authorization_boundary_id: current_user.authorization_boundaries.ids + [ nil ])
  end

  def authorize_analyze! = authorize_permission!("cdef.read")
  def authorize_save! = authorize_permission!("cdef.write")
end
