# frozen_string_literal: true

# What a boundary serves back out to the systems it exchanges with (#1354):
# one list of its current documents, each with its format, document type,
# when it last changed and where to download it.
#
#   - SPARC's own documents for the boundary (SSP, SAP, SAR, POA&M, the CDEFs
#     its components use) through the existing OSCAL export endpoints, and
#     the boundary as an HDF system document. These are built on request, so
#     the index cannot give their SHA-256 without building every export each
#     time it is read; `sha256` is null for them;
#   - its FedRAMP Vulnerability Detail Report (VER-RPT-VDT), Accepted
#     Vulnerability Info (VER-RPT-AVI) and Historical Vulnerability Activity
#     (VER-TFR-MRH), also built on request (sha256 null), listed only when
#     the boundary has a FedRAMP Certification Package Overview address,
#     which each report names;
#   - its FedRAMP Certification Package Overview (FRC-CSO-PKG, #1390), built
#     on request, listed once the boundary records every field it requires;
#   - every received document the boundary has ACCEPTED, with its SHA-256 —
#     except Class A certification materials, which are the provider's to
#     share, not the boundary's.
#
# The downloads are the existing authenticated endpoints: a caller needs a
# token that may read each one. Reading the index is recorded in the audit
# log (FedRAMP CDS-TRC-ACL keeps access logs; CDS-TRC-AAI an access
# inventory), by the controller.
#
# NIST SP 800-53: CA-3 (information exchange), AC-3, AU-12.
class ExchangeIndexService
  OSCAL_EXPORTS = {
    "ssp" => [ :ssp_documents, "ssp_documents" ],
    "assessment_plan" => [ :sap_documents, "sap_documents" ],
    "assessment_results" => [ :sar_documents, "sar_documents" ],
    "poam" => [ :poam_documents, "poam_documents" ]
  }.freeze

  def self.call(boundary) = new(boundary).call

  def initialize(boundary)
    @boundary = boundary
  end

  def call
    {
      authorization_boundary: { id: @boundary.id, name: @boundary.name },
      generated_at: Time.current.utc.iso8601,
      documents: sparc_documents + hdf_system + fedramp_reports + received
    }
  end

  private

  def sparc_documents
    entries = OSCAL_EXPORTS.flat_map do |document_type, (model, path)|
      klass = model.to_s.classify.constantize
      klass.where(authorization_boundary_id: @boundary.id).order(:id).map do |doc|
        entry("sparc", "oscal", document_type, doc, "/api/v1/#{path}/#{doc.id}/export?format=oscal")
      end
    end
    cdefs = @boundary.cdef_documents.distinct.order(:id).map do |doc|
      entry("sparc", "oscal", "component_definition", doc, "/api/v1/cdef_documents/#{doc.id}/export?format=oscal")
    end
    entries + cdefs
  end

  def hdf_system
    [ { origin: "sparc", format: "hdf", document_type: "system", id: @boundary.id,
        name: @boundary.name, updated_at: @boundary.updated_at&.utc&.iso8601, sha256: nil,
        download_url: "/api/v1/authorization_boundaries/#{@boundary.id}/hdf_system" } ]
  end

  # Built on request; listed only when they can be built (#1354, #1384, #1390).
  FEDRAMP_REPORTS = {
    FedrampVulnerabilityReportService::VDR => [ "vulnerability_detail_report", "Vulnerability Detail Report" ],
    FedrampVulnerabilityReportService::AVI => [ "accepted_vulnerability_info", "Accepted Vulnerability Info" ],
    FedrampVulnerabilityReportService::HISTORICAL => [ "historical_ver_activity", "Historical Vulnerability Activity" ]
  }.freeze
  # #1390 — listed once the boundary records everything it requires; it
  # names no overview address, so it does not need one.
  FEDRAMP_OVERVIEW = [ "certification_package_overview", "Certification Package Overview" ].freeze

  def fedramp_reports
    return [] unless @boundary.fedramp_enabled?

    reports = @boundary.fedramp_overview_address.blank? ? {} : FEDRAMP_REPORTS
    reports = { FedrampPackageOverview::DOCUMENT_TYPE => FEDRAMP_OVERVIEW }.merge(reports) if @boundary.fedramp_overview_ready?
    reports.map do |document_type, (path, title)|
      { origin: "sparc", format: "fedramp", document_type: document_type, id: @boundary.id,
        name: "#{@boundary.name} FedRAMP #{title}", updated_at: Time.current.utc.iso8601, sha256: nil,
        download_url: "/api/v1/authorization_boundaries/#{@boundary.id}/fedramp/#{path}" }
    end
  end

  def received
    @boundary.received_documents.documents.in_effect.order(:received_at).map do |doc|
      { origin: "received", format: doc.format, document_type: doc.document_type, id: doc.id,
        name: doc.filename, fedramp_id: doc.fedramp_id, updated_at: doc.reviewed_at&.utc&.iso8601,
        received_at: doc.received_at.utc.iso8601, sha256: doc.sha256,
        download_url: "/api/v1/authorization_boundaries/#{@boundary.id}/received_documents/#{doc.id}/file" }.compact
    end
  end

  def entry(origin, format, document_type, doc, url)
    { origin: origin, format: format, document_type: document_type, id: doc.id,
      name: doc.try(:name) || doc.try(:title), updated_at: doc.updated_at&.utc&.iso8601, sha256: nil,
      download_url: url }
  end
end
