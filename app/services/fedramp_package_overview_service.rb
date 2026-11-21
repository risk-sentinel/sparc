# frozen_string_literal: true

# #1390 — writes a boundary's FedRAMP Certification Package Overview
# (FRC-CSO-PKG; CPO-CSO-OVR, the JSON form) from what the boundary records
# (FedrampPackageOverview): service identification, service properties, the
# trust center, and the provider's contacts.
#
# Not written: the assessor, advisors, certified services and third-party
# information resources (optional in the schema; not recorded by SPARC yet).
#
#   FedrampPackageOverviewService.call(boundary)  # => the overview, as a Hash
#
#   Incomplete    — the boundary lacks a field the overview requires, or a
#                   Security or Sales contact. The caller's to fix; the
#                   message lists what is missing.
#   FedrampVulnerabilityReportService::InvalidReport
#                 — the overview SPARC built fails the pinned FedRAMP schema
#                   or the completeness check. SPARC's defect; never returned.
#
# NIST SP 800-53: PL-2 (system description), CA-3 (information exchange),
# SI-10 (output validated against the pinned schema).
class FedrampPackageOverviewService
  DOCUMENT_TYPE = FedrampPackageOverview::DOCUMENT_TYPE

  class Incomplete < FedrampVulnerabilityReportService::Error; end

  def self.call(boundary) = new(boundary).call

  def initialize(boundary)
    @boundary = boundary
  end

  def call
    missing = @boundary.fedramp_overview_missing
    if missing.any?
      raise Incomplete, "Boundary '#{@boundary.name}' cannot produce its FedRAMP Certification Package Overview " \
                        "yet. Missing: #{missing.join(', ')}."
    end

    validated!(@boundary.fedramp_overview_document)
  end

  private

  def validated!(doc)
    result = DocumentValidationService.call(JSON.generate(doc), format: "fedramp", document_type: DOCUMENT_TYPE)
    raise FedrampVulnerabilityReportService::InvalidReport.new(DOCUMENT_TYPE, result.errors) unless result.valid?

    doc
  rescue DocumentValidationService::Error => e
    raise FedrampVulnerabilityReportService::InvalidReport.new(DOCUMENT_TYPE,
                                                                [ { check: "schema", pointer: "", message: e.message } ])
  end
end
