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
  before_action :authorize_read!,  only: %i[show amendments]
  before_action :authorize_write!, only: %i[ingest disposition clear_disposition]

  def show
    @findings = @boundary.scanner_findings.order(:control_id)
    @findings = @findings.where(status: params[:status]) if params[:status].present?
    @findings = @findings.where(severity: params[:severity].to_s.upcase) if params[:severity].present?
    @scan_runs = @boundary.scan_runs.recent.limit(10)
    @dispositions_by_control = @boundary.finding_dispositions.index_by(&:control_id)
    @kinds = FindingDisposition::KINDS
    @linkage = FindingDispositionService::LINKAGE
  end

  def ingest
    file = params[:file]
    return redirect_to(triage_path, alert: "Choose an HDF file to upload.") if file.blank?

    run = HdfIngestService.new(@boundary).ingest(
      file.read, source_filename: file.original_filename, created_by: actor
    )
    redirect_to triage_path,
                notice: "Ingested #{run.finding_count} findings (#{run.failed_count} failed) from #{run.scanner}."
  rescue HdfIngestService::IngestError => e
    redirect_to triage_path, alert: "Ingest failed: #{e.message}"
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

  def authorize_read!
    authorize_permission!("evidence.read", authorization_boundary_id: @boundary.id)
  end

  def authorize_write!
    authorize_permission!("evidence.write", authorization_boundary_id: @boundary.id)
  end
end
