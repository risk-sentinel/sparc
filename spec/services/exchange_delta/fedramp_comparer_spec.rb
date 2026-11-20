# frozen_string_literal: true

require "rails_helper"

# #1354 — FedRAMP package deltas by document type, plus the rule every type
# shares: a field FedRAMP's schema requires going blank is a regression.
RSpec.describe ExchangeDelta::FedrampComparer do
  def compare(before, after, type)
    ExchangeDelta.compare(format: "fedramp", document_type: type,
                          before: JSON.generate(before), after: JSON.generate(after))
  end

  def kinds(result) = result.changes.map { |c| [ c.kind, c.summary ] }

  def vuln(id, **fields)
    { "providerTrackingId" => id,
      "detection" => { "detectedAt" => "2026-10-02T10:00:00Z", "detectionSource" => "scanner" },
      "vulnerabilityDescription" => "Outdated library #{id}" }.merge(fields.transform_keys(&:to_s))
  end

  describe "vulnerability-detail-report" do
    let(:type) { "vulnerability-detail-report" }

    def vdr(*vulns, period_to: "2026-10-31T23:59:59Z")
      { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
        "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => period_to },
        "vulnerabilities" => vulns }
    end

    it "classes a new vulnerability as a regression, with its N-rating" do
      result = compare(vdr(vuln("VULN-1")), vdr(vuln("VULN-1"), vuln("VULN-12", currentRating: 4)), type)
      expect(kinds(result)).to eq([ [ :regression, "VULN-12 added (N4)" ] ])
      expect(result).not_to be_auto_acceptable
    end

    it "treats a new vulnerability already remediated as neutral" do
      result = compare(vdr, vdr(vuln("VULN-2", finalDisposition: "Remediated")), type)
      expect(kinds(result)).to eq([ [ :neutral, "VULN-2 added, already Remediated" ] ])
    end

    it "treats a vulnerability no longer reported as neutral, not as remediated" do
      result = compare(vdr(vuln("VULN-1"), vuln("VULN-2")), vdr(vuln("VULN-1")), type)
      expect(kinds(result)).to eq([ [ :neutral, "VULN-2 no longer reported" ] ])
    end

    it "classes a rating going up as a regression and down as an improvement" do
      result = compare(vdr(vuln("A", currentRating: 2), vuln("B", currentRating: 4)),
                       vdr(vuln("A", currentRating: 3), vuln("B", currentRating: 1)), type)
      expect(kinds(result)).to contain_exactly([ :regression, "A: rating N2 → N3" ], [ :improvement, "B: rating N4 → N1" ])
    end

    it "classes a disposition: Remediated an improvement, withdrawn a regression, False Positive neutral" do
      result = compare(vdr(vuln("A"), vuln("B", finalDisposition: "Fully Mitigated"), vuln("C")),
                       vdr(vuln("A", finalDisposition: "Remediated"), vuln("B"), vuln("C", finalDisposition: "False Positive")),
                       type)
      expect(kinds(result)).to contain_exactly(
        [ :improvement, "A: disposition (active) → Remediated" ],
        [ :regression, "B: disposition Fully Mitigated → (active)" ],
        [ :neutral, "C: disposition (active) → False Positive" ]
      )
    end

    it "classes a vulnerability turning overdue as a regression and the reverse as an improvement" do
      overdue = { "isOverdue" => true, "explanation" => "Vendor patch late" }
      result = compare(vdr(vuln("A"), vuln("B", overdueStatus: overdue)),
                       vdr(vuln("A", overdueStatus: overdue), vuln("B", overdueStatus: { "isOverdue" => false })), type)
      expect(kinds(result)).to contain_exactly([ :regression, "A: overdue false → true" ], [ :improvement, "B: overdue true → false" ])
    end

    it "classes internet-reachable or likely-exploitable turning true as a regression" do
      result = compare(vdr(vuln("A", isInternetReachable: false, isLikelyExploitable: true)),
                       vdr(vuln("A", isInternetReachable: true, isLikelyExploitable: false)), type)
      expect(kinds(result)).to contain_exactly([ :regression, "A: internet-reachable false → true" ],
                                               [ :improvement, "A: likely exploitable true → false" ])
    end

    it "auto-accepts a report whose only change is a remediation, and ignores reordering" do
      result = compare(vdr(vuln("A"), vuln("B")), vdr(vuln("B"), vuln("A", finalDisposition: "Remediated")), type)
      expect(result.counts).to eq(regression: 0, improvement: 1, neutral: 0)
      expect(result).to be_auto_acceptable
    end

    it "reports a new report period and other field changes as neutral" do
      result = compare(vdr(vuln("A")), vdr(vuln("A", potentialAgencyImpact: "Low"), period_to: "2026-11-30T23:59:59Z"), type)
      expect(kinds(result)).to contain_exactly(
        [ :neutral, "/reportPeriod/to: 2026-10-31T23:59:59Z → 2026-11-30T23:59:59Z" ],
        [ :neutral, "/vulnerabilities/A/potentialAgencyImpact: added (Low)" ]
      )
    end

    it "classes a required field going blank as a regression, once, and filling it in as an improvement" do
      result = compare(vdr(vuln("A"), vuln("B", vulnerabilityDescription: " ")),
                       vdr(vuln("A", vulnerabilityDescription: " "), vuln("B", vulnerabilityDescription: "Now described")), type)
      expect(kinds(result)).to contain_exactly(
        [ :regression, "/vulnerabilities/A/vulnerabilityDescription: required field is now blank" ],
        [ :improvement, "/vulnerabilities/B/vulnerabilityDescription: required field filled in" ]
      )
    end
  end

  describe "accepted-vulnerability-info" do
    let(:type) { "accepted-vulnerability-info" }

    def avi(*entries)
      { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
        "reportPeriod" => { "from" => "2026-10-01", "to" => "2026-10-31" },
        "acceptedVulnerabilities" => entries.map { |v| { "vulnerabilityDetail" => v, "acceptanceRationale" => "Vendor dependency" } } }
    end

    it "classes a newly accepted risk as a regression and one no longer listed as neutral" do
      result = compare(avi(vuln("A")), avi(vuln("B", currentRating: 3)), type)
      expect(kinds(result)).to contain_exactly([ :regression, "B: risk accepted (N3)" ],
                                               [ :neutral, "A: no longer listed as accepted" ])
    end

    it "grades an accepted vulnerability's rating like a reported one" do
      result = compare(avi(vuln("A", currentRating: 1)), avi(vuln("A", currentRating: 2)), type)
      expect(kinds(result)).to eq([ [ :regression, "A: rating N1 → N2" ] ])
    end
  end

  describe "security-decision-record" do
    let(:type) { "security-decision-record" }

    def sdr(frrs: [], ksis: [], controls: [], updated: "2026-11-01T00:00:00Z")
      { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
        "metadata" => { "version" => "1", "lastUpdated" => updated, "updateSource" => "pipeline" },
        "fedRampRequirements" => frrs.map { |id, status| { "frrID" => id, "frrImplementationStatus" => status, "frrImplementation" => [] } },
        "keySecurityIndicators" => ksis.map { |id, status| { "ksiId" => id, "ksiImplementationStatus" => status } },
        "securityControls" => controls.map do |id, status, text|
          { "controlId" => id, "controlImplementationStatus" => status, "controlImplementationDescription" => text || "How" }
        end }
    end

    it "classes a status moving down as a regression and up as an improvement, for each list" do
      result = compare(sdr(frrs: [ %w[FRR-1 Implemented] ], ksis: [ [ "KSI-1", "Not Implemented" ] ], controls: [ [ "AC-2", "Partially Implemented" ] ]),
                       sdr(frrs: [ [ "FRR-1", "Partially Implemented" ] ], ksis: [ %w[KSI-1 Implemented] ], controls: [ [ "AC-2", "Not Implemented" ] ]),
                       type)
      expect(kinds(result)).to contain_exactly(
        [ :regression, "FRR-1: Implemented → Partially Implemented" ],
        [ :improvement, "KSI-1: Not Implemented → Implemented" ],
        [ :regression, "AC-2: Partially Implemented → Not Implemented" ]
      )
    end

    it "classes a requirement no longer addressed as a regression and a new one as neutral" do
      result = compare(sdr(controls: [ %w[AC-2 Implemented] ]), sdr(controls: [ %w[AC-3 Implemented] ]), type)
      expect(kinds(result)).to contain_exactly([ :regression, "AC-2: no longer addressed in the security decision record" ],
                                               [ :neutral, "AC-3 added (Implemented)" ])
    end

    it "reports text changes as neutral and ignores metadata/lastUpdated" do
      result = compare(sdr(controls: [ %w[AC-2 Implemented How] ]),
                       sdr(controls: [ [ "AC-2", "Implemented", "How, now" ] ], updated: "2026-12-01T00:00:00Z"), type)
      expect(kinds(result)).to eq([ [ :neutral, "/securityControls/AC-2/controlImplementationDescription: How → How, now" ] ])
    end
  end

  describe "certification-package-overview" do
    let(:type) { "certification-package-overview" }

    def cpo(**identification)
      { "serviceIdentification" => { "providerName" => "Provider", "serviceName" => "Service", "serviceAcronym" => "SVC",
                                     "serviceDescription" => "A service", "certificationType" => "Rev5",
                                     "fedRampPackageId" => "FR2401234567", "website" => "https://provider.example" }
                                     .merge(identification.transform_keys(&:to_s)),
        "serviceProperties" => { "serviceType" => [ "SaaS" ], "deploymentModel" => "Public Cloud",
                                 "trustCenter" => { "repositoryType" => [ "Trust Center" ], "url" => "https://trust.provider.example",
                                                    "repositoryDescription" => "Trust center", "authenticationRequired" => true } },
        "contactInformation" => [] }
    end

    it "classes a certification type, class or package ID change as a regression" do
      result = compare(cpo, cpo(certificationType: "20x", fedRampPackageId: "FR2409999999", certificationClass: "B"), type)
      expect(kinds(result)).to contain_exactly(
        [ :regression, "Certification type: Rev5 → 20x" ],
        [ :regression, "FedRAMP package ID: FR2401234567 → FR2409999999" ],
        [ :regression, "Certification class: (none) → B" ]
      )
    end

    it "classes a moved trust center as a regression" do
      after = cpo
      after["serviceProperties"]["trustCenter"]["url"] = "https://elsewhere.example"
      expect(kinds(compare(cpo, after, type)))
        .to eq([ [ :regression, "Trust center address: https://trust.provider.example → https://elsewhere.example" ] ])
    end

    it "reports other fields as neutral" do
      expect(kinds(compare(cpo, cpo(serviceDescription: "A better service"), type)))
        .to eq([ [ :neutral, "/serviceIdentification/serviceDescription: A service → A better service" ] ])
    end
  end

  it "compares any other document type field by field, neutral" do
    before = { "certificationPackageOverviewUri" => "https://provider.example/cpo.json", "note" => "a" }
    after = before.merge("note" => "b")
    expect(kinds(compare(before, after, "incident-report"))).to eq([ [ :neutral, "/note: a → b" ] ])
  end
end
