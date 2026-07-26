# frozen_string_literal: true

# #447 — HDF Amendment triage UI. A thin web client over the same services the
# API uses (HdfIngestService / FindingDispositionService / HdfAmendmentExportService),
# scoped to one AuthorizationBoundary:
#
#   GET    /authorization_boundaries/:id/triage                — dashboard
#   POST   /authorization_boundaries/:id/triage/ingest         — upload HDF
#   POST   /authorization_boundaries/:id/triage/disposition    — set a disposition
#   DELETE /authorization_boundaries/:id/triage/disposition    — clear a disposition
#   GET    /authorization_boundaries/:id/triage/amendments     — download Amendments JSON
#
# NIST 800-53: AC-3/AC-6 (boundary-scoped RBAC via evidence.read/write),
# CA-7 (continuous monitoring), SI-2 (flaw remediation), AU-12 (audit).
class HdfTriageController < ApplicationController
  before_action :set_boundary
  before_action :authorize_read!,  only: %i[show amendments package]
  before_action :authorize_write!, only: %i[ingest disposition clear_disposition aggregate]
  # #809 — approving an amendment is a SEPARATE authority from triaging one, and
  # it has to be enforced on the action, not just by hiding the button: the view's
  # @can_approve only controls rendering, so gating these on evidence.write would
  # let any triager approve their own amendment by POSTing the route directly.
  before_action :authorize_approve!, only: %i[approve_disposition reject_disposition]

  def show
    # #811 — findings carry history; the triage board shows the CURRENT scan by
    # default, with an opt-in toggle to include superseded rows for audit.
    @include_history = params[:include_history] == "true"
    @findings = @boundary.scanner_findings.order(:control_id)
    @findings = @findings.current unless @include_history
    @findings = @findings.where(status: params[:status]) if params[:status].present?
    @findings = @findings.where(severity: params[:severity].to_s.upcase) if params[:severity].present?
    @findings = @findings.where(lifecycle_status: params[:lifecycle]) if params[:lifecycle].present?
    @findings = @findings.where(cdef_document_id: params[:cdef_document_id]) if params[:cdef_document_id].present?
    @scan_runs = @boundary.scan_runs.recent.limit(10)
    @dispositions_by_control = @boundary.finding_dispositions.index_by(&:control_id)
    @kinds = FindingDisposition::KINDS
    @linkage = FindingDispositionService::LINKAGE
    @cdef_documents = @boundary.respond_to?(:cdef_documents) ? @boundary.cdef_documents.order(:name) : CdefDocument.order(:name)
    @scanner_scopes = ScanRun::SCANNER_SCOPES
    @lifecycle_statuses = ScannerFinding::LIFECYCLE_STATUSES
    @re_failed_count = @boundary.scanner_findings.current.where(lifecycle_status: "re_failed").count
    @can_approve = current_user&.admin? ||
                   current_user&.has_permission?("amendment.approve", authorization_boundary_id: @boundary.id)
  end

  def ingest
    file = params[:file]
    return redirect_to(triage_path, alert: "Choose an HDF file to upload.") if file.blank?

    # #811 — record which target/CDEF this scan belongs to and whether it is a
    # boundary-wide scan (e.g. AWS Config) or target-specific (trivy, secrets…).
    run = HdfIngestService.new(@boundary).ingest(
      file.read, source_filename: file.original_filename, created_by: actor,
      cdef_document: resolve_cdef(params[:cdef_document_id]),
      scanner_scope: params[:scanner_scope].presence || "target"
    )
    redirect_to triage_path,
                notice: "Ingested #{run.finding_count} findings (#{run.failed_count} failed) from #{run.scanner}."
  rescue HdfIngestService::IngestError => e
    redirect_to triage_path, alert: "Ingest failed: #{e.message}"
  end

  # #809 — approve/reject a disposition (an amendment). Approval + validity window
  # gate whether the disposition suppresses a finding during aggregation/export.
  def approve_disposition
    disp = @boundary.finding_dispositions.find_by!(uuid: params[:disposition_uuid])
    FindingDispositionService.approve(disp, approved_by: actor)
    redirect_to triage_path, notice: "Approved amendment for #{disp.control_id}."
  rescue FindingDispositionService::DispositionError => e
    redirect_to triage_path, alert: "Approval failed: #{e.message}"
  end

  def reject_disposition
    disp = @boundary.finding_dispositions.find_by!(uuid: params[:disposition_uuid])
    FindingDispositionService.reject(disp, approved_by: actor)
    redirect_to triage_path, notice: "Rejected amendment for #{disp.control_id}."
  rescue FindingDispositionService::DispositionError => e
    redirect_to triage_path, alert: "Rejection failed: #{e.message}"
  end

  # #809 — aggregate current findings/dispositions into SSP/SAP/SAR/POA&M.
  def aggregate
    result = HdfAggregationService.new(@boundary).aggregate
    redirect_to triage_path,
                notice: "Aggregated into documents — SSP #{result.ssp}, SAP #{result.sap}, " \
                        "SAR #{result.sar}, POA&M #{result.poam}."
  end

  # #809 — download the signed HDF package (amendments + findings + dispositions).
  def package
    bundle = HdfPackageService.new(@boundary).build
    send_data JSON.pretty_generate(bundle),
              filename: "#{@boundary.slug || @boundary.uuid}-hdf-package.json",
              type: "application/json", disposition: "attachment"
  end

  def disposition
    finding = @boundary.scanner_findings.find_by!(uuid: params[:finding_uuid])
    subject = FindingDispositionService.resolve_subject(params[:linked_subject_type], params[:linked_subject_id])
    FindingDispositionService.new(finding).upsert(
      kind: params[:kind].to_s, reason: params[:reason].to_s, decided_by: actor,
      linked_subject: subject, expiration: params[:expiration].presence
    )
    redirect_to triage_path, notice: "Disposition saved for #{finding.control_id}."
  rescue FindingDispositionService::DispositionError => e
    redirect_to triage_path, alert: "Disposition failed: #{e.message}"
  end

  def clear_disposition
    @boundary.finding_dispositions.find_by(control_id: params[:control_id])&.destroy
    redirect_to triage_path, notice: "Disposition cleared."
  end

  # Convenience download. The authoritative, hdf-verified artefact is the API
  # endpoint tenant CI pulls; this UI download skips verify so it works in
  # environments without the hdf binary installed.
  def amendments
    doc = HdfAmendmentExportService.new(@boundary).export(verify: false)
    send_data JSON.pretty_generate(doc),
              filename: "#{@boundary.slug || @boundary.uuid}-amendments.hdf.json",
              type: "application/json", disposition: "attachment"
  end

  private

  def set_boundary
    # These are member routes on authorization_boundaries, so the boundary is :id.
    key = params[:id]
    @boundary =
      if key.to_s.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  def triage_path
    triage_authorization_boundary_path(@boundary)
  end

  def actor
    current_user&.display_name.presence || current_user&.email
  end

  def resolve_cdef(key)
    return nil if key.blank?

    if key.to_s.match?(/\A\d+\z/)
      CdefDocument.find_by(id: key)
    else
      CdefDocument.find_by(slug: key) || CdefDocument.find_by(name: key)
    end
  end

  def authorize_read!
    authorize_permission!("evidence.read", authorization_boundary_id: @boundary.id)
  end

  def authorize_write!
    authorize_permission!("evidence.write", authorization_boundary_id: @boundary.id)
  end

  # Mirrors Api::V1::FindingDispositionsController#authorize_approve! — admin, or
  # a role the Instance Admin granted `amendment.approve`.
  def authorize_approve!
    authorize_permission!("amendment.approve", authorization_boundary_id: @boundary.id)
  end
end
