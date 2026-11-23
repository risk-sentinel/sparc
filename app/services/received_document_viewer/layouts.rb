# frozen_string_literal: true

class ReceivedDocumentViewer
  # How the viewer lays out each document type (#1390 part G; owner approved
  # the layouts from the HTML mockup, 2026-11-23). ONE definition per type:
  # the order of its sections, their titles and the top-level fields each one
  # shows. A field a layout does not name is shown under "Other fields", so
  # nothing a provider sent is ever hidden from the reviewer. A type with no
  # layout (OSCAL, and any type SPARC adds later) gets the general view: one
  # section per top-level field, labelled from the document itself.
  module Layouts
    FEDRAMP = {
      "vulnerability-detail-report" => [
        [ "Vulnerabilities", %w[vulnerabilities] ],
        [ "Report", %w[reportPeriod certificationPackageOverviewUri] ]
      ],
      "accepted-vulnerability-info" => [
        [ "Accepted vulnerabilities", %w[acceptedVulnerabilities] ],
        [ "Report", %w[reportPeriod certificationPackageOverviewUri] ]
      ],
      "historical-ver-activity" => [
        [ "Active vulnerabilities", %w[activeVulnerabilities] ],
        [ "Accepted vulnerabilities", %w[acceptedVulnerabilities] ],
        [ "Snapshot", %w[generatedAt certificationPackageOverviewUri] ]
      ],
      "security-decision-record" => [
        [ "Security controls (NIST SP 800-53 Rev 5)", %w[securityControls] ],
        [ "Key Security Indicators", %w[keySecurityIndicators] ],
        [ "FedRAMP requirements", %w[fedRampRequirements] ],
        [ "Ports and protocols", %w[portsAndProtocols] ],
        [ "Record", %w[metadata certificationPackageOverviewUri] ]
      ],
      "certification-package-overview" => [
        [ "Service", %w[serviceIdentification] ],
        [ "Certified services", %w[certifiedServices] ],
        [ "Contacts", %w[contactInformation] ],
        [ "Trust center and repositories", %w[serviceProperties] ],
        [ "Third-party information resources", %w[thirdPartyInformationResources] ],
        [ "Assessor and advisors", %w[assessor advisors] ]
      ],
      "ongoing-certification-report" => [
        [ "Reporting period", %w[reportPeriod activeAgencies] ],
        [ "Changes to certification data", %w[certificationDataChanges plannedCertificationDataChanges transformativeChanges] ],
        [ "Incidents", %w[reportableIncidents] ],
        [ "Vulnerabilities and recommendations", %w[acceptedVulnerabilities updatedRecommendations] ],
        [ "Report", %w[certificationPackageOverviewUri] ]
      ],
      "incident-report" => [
        [ "Incident", %w[reportType providerTrackingId incidentDescription rootCause resolvedAt] ],
        [ "Timeline", %w[timeline] ],
        [ "Impact", %w[potentialImpact functionalImpact affectedAgencies recoveryPlan] ],
        [ "Activity and indicators", %w[observedActivity indicatorsOfCompromise relatedCveIds responseAndRecoveryActivities] ],
        [ "Coordination", %w[federalIncidentCoordinator certificationPackageOverviewUri] ]
      ],
      "significant-change-notifications" => [
        [ "Change", %w[changeType changeTypeExplanation changeDescription reason relatedVulnerability] ],
        [ "Plan and timeline", %w[planAndTimeline] ],
        [ "Impact", %w[customerImpact impactedControls impactAnalysis] ],
        [ "Assessor", %w[assessorName certificationPackageOverviewUri] ]
      ],
      "assessor-information" => [
        [ "Assessor", %w[assessorName serviceDescription a2laId a2laAccreditationDate foundedDate cyberFrameworks logo] ],
        [ "Services offered", %w[servicesOffered] ],
        [ "Contact", %w[contactInformation] ]
      ],
      "advisor-information" => [
        [ "Advisor", %w[advisorName serviceDescription logo] ],
        [ "Services offered", %w[servicesOffered] ],
        [ "Contact", %w[contactInformation] ]
      ]
    }.freeze

    # HDF and XCCDF are shown as the comparers read them (one entry per
    # requirement or rule), whatever their document type.
    BY_FORMAT = {
      "hdf" => [
        [ "Results by control", %w[controls] ]
      ],
      "xccdf" => [
        [ "Rule results", %w[ruleResults] ],
        [ "Test result", %w[benchmark target startTime endTime] ]
      ]
    }.freeze

    # How an entry of a named list is titled: its title field, a one-line
    # summary, and the fields shown as badges (status or rating).
    ENTRIES = {
      "vulnerabilities" => { title: "providerTrackingId", summary: "vulnerabilityDescription", rating: "currentRating", status: "finalDisposition" },
      "activeVulnerabilities" => { title: "providerTrackingId", summary: "vulnerabilityDescription", rating: "currentRating", status: "finalDisposition" },
      "acceptedVulnerabilities" => { title: "vulnerabilityDetail/providerTrackingId", summary: "vulnerabilityDetail/vulnerabilityDescription", rating: "vulnerabilityDetail/currentRating" },
      "securityControls" => { title: "controlId", summary: "controlImplementationDescription", status: "controlImplementationStatus" },
      "fedRampRequirements" => { title: "frrID", summary: "frrImplementation/0", status: "frrImplementationStatus" },
      "keySecurityIndicators" => { title: "ksiId", summary: "ksiImplementation/0", status: "ksiImplementationStatus" },
      "portsAndProtocols" => { title: "portNumber", summary: "serviceName", status: "transportProtocol" },
      "contactInformation" => { title: "contactType", summary: "contactName" },
      "certifiedServices" => { title: "serviceName", summary: "serviceDescription" },
      "servicesOffered" => { title: "serviceName", summary: "serviceDescription" },
      "milestones" => { title: "milestoneDescription", summary: "targetDate" },
      "incidents" => { title: "summary", summary: "occurredAt" },
      "nonCertified" => { title: "name", summary: "useCase" },
      "certified" => { title: "fedRampCertifiedThirdPartyInformationResource", summary: "useCase" },
      "additionalRepositories" => { title: "url", summary: "repositoryDescription" },
      "controls" => { title: "id", summary: "title", status: "status" },
      "ruleResults" => { title: "id", summary: "title", status: "result" },
      "poam-items" => { title: "title", summary: "uuid" },
      "findings" => { title: "title", summary: "uuid" },
      "implemented-requirements" => { title: "control-id", summary: "uuid" }
    }.freeze

    # Labels where humanizing the field name reads wrong.
    LABELS = {
      "certificationPackageOverviewUri" => "Package overview address", "fedRampPackageId" => "FedRAMP package ID",
      "frrID" => "Requirement", "fedRampRequirements" => "FedRAMP requirements", "ksiId" => "KSI", "a2laId" => "A2LA ID", "a2laAccreditationDate" => "A2LA accreditation date",
      "isInternetReachable" => "Internet reachable", "isLikelyExploitable" => "Likely exploitable",
      "currentRating" => "Current rating (N)", "targetRating" => "Target rating (N)", "rating" => "Rating (N)",
      "historicalRating" => "Earlier ratings (N)", "frrImplementationStatus" => "Status", "ksiImplementationStatus" => "Status",
      "controlImplementationStatus" => "Status", "controlImplementationDescription" => "Implementation",
      "frrImplementation" => "Implementation", "ksiImplementation" => "Implementation", "frrValidation" => "Validation",
      "ksiValidation" => "Validation", "frrAssessment" => "Assessment", "ksiAssessment" => "Assessment",
      "ksiTests" => "Tests", "ksiEvidence" => "Evidence", "providerTrackingId" => "Provider tracking ID",
      "painReductionEvents" => "Rating reductions", "ruleResults" => "Rule results", "poam-items" => "POA&M items",
      "oscal-version" => "OSCAL version", "last-modified" => "Last modified", "uei" => "UEI", "ueiNumber" => "UEI number"
    }.freeze

    # Numbers that are FedRAMP N-ratings, shown as N0–N5.
    RATING_FIELDS = %w[currentRating targetRating rating historicalRating].freeze

    extend self

    # [[title, [top-level keys]], ...] for a document, with "Other fields"
    # last when the document has fields its layout does not name.
    def sections(format, document_type, data)
      return [] unless data.is_a?(Hash)

      layout = format == "fedramp" ? FEDRAMP[document_type.to_s] : BY_FORMAT[format]
      present = data.keys - [ "$schema" ]
      return present.map { |key| [ label(key), [ key ] ] } unless layout

      named = layout.flat_map(&:last)
      rest = present - named
      layout.select { |_, keys| keys.any? { |k| data.key?(k) } } + (rest.any? ? [ [ "Other fields", rest ] ] : [])
    end

    def label(key)
      LABELS.fetch(key.to_s) do
        key.to_s.tr("-_", "  ").gsub(/([a-z0-9])([A-Z])/) { "#{Regexp.last_match(1)} #{Regexp.last_match(2).downcase}" }
           .sub(/\A./, &:upcase).gsub(/\b(id|uri|url|ksi|frr|cve|uuid|nist|oscal)\b/i, &:upcase)
      end
    end
  end
end
