# frozen_string_literal: true

require "rails_helper"

# #1390 — the Ongoing Certification Report (CCM-OCR-AVL), written from the
# boundary's FedRAMP records and issued once per period.
RSpec.describe FedrampOngoingReportService do
  include ActiveSupport::Testing::TimeHelpers

  let(:boundary) do
    create(:authorization_boundary, :fedramp, fedramp_package_overview_uri: "https://trust.example/cpo.json",
                                              fedramp_active_agencies: "Example Agency\nOther Agency\n")
  end
  let(:service) { described_class.new(boundary) }
  let(:user) { create(:user) }

  before { travel_to Time.utc(2026, 11, 20, 12) }

  def change(**attributes)
    FedrampSignificantChangeService.new(boundary).record(attributes: attributes, user: user).change
  end

  it "defaults to 3 months back, then to the day after the last report issued" do
    expect(service.default_period).to eq([ Date.new(2026, 8, 21), Date.new(2026, 11, 20) ])
    expect(service.next_target_date).to be_nil
    service.issue(service.input(from: "2026-08-01", to: "2026-10-31"), user: user)
    expect(service.default_period).to eq([ Date.new(2026, 11, 1), Date.new(2026, 11, 20) ])
    expect(service.next_target_date).to eq(Date.new(2027, 1, 31))
  end

  it "writes every section from the boundary's records, valid against FedRAMP's schema" do
    FedrampStatementService.new(boundary).record(kind: "frr", rule_id: "SDR-CSO-FRR",
                                                 attributes: { status: "Implemented" }, user: user)
    change(change_type: "Transformative", description: "Region move", started_on: "2026-11-02", finished_on: "2026-11-10")
    change(change_type: "Adaptive", description: "Dashboard", plan_summary: "Flag", planned_start: "2026-12-15")
    change(change_type: "Adaptive", description: "Next year", plan_summary: "Later", planned_start: "2027-06-01")
    change(change_type: "Routine", description: "Patching", finished_on: "2026-11-05")
    incidents = FedrampIncidentService.new(boundary)
    incidents.record(attributes: { tracking_id: "INC-1", description: "Phishing", detected_at: "2026-10-01T09:00",
                                   resolved_at: "2026-10-02T09:00", lessons_learned: "MFA everywhere" }, user: user)
    incidents.record(attributes: { tracking_id: "INC-OLD", detected_at: "2026-01-01T09:00", resolved_at: "2026-01-02T09:00" }, user: user)
    incidents.record(attributes: { tracking_id: "INC-NR", reportable: false, detected_at: "2026-10-01T09:00" }, user: user)

    doc = service.build(service.input(recommendations: "Rotate keys yearly\n", other_changes: "New logo"))
    expect(doc["reportPeriod"]).to eq("from" => "2026-08-21", "to" => "2026-11-20")
    expect(doc["certificationDataChanges"]).to eq([ "1 FedRAMP rule answer updated: SDR-CSO-FRR",
                                                    "Transformative change finished 2026-11-10: Region move", "New logo" ])
    expect(doc["plannedCertificationDataChanges"]).to eq(
      "planningHorizonThrough" => "2027-02-20", "changes" => [ "Adaptive change planned to start 2026-12-15: Dashboard" ]
    )
    expect(doc["transformativeChanges"]).to eq([ "Region move (started 2026-11-02, finished 2026-11-10)" ])
    expect(doc["acceptedVulnerabilities"]).to eq("No accepted vulnerabilities in the period.")
    expect(doc["updatedRecommendations"]).to eq([ "Rotate keys yearly" ])
    expect(doc["activeAgencies"]).to eq([ "Example Agency", "Other Agency" ])
    expect(doc.dig("reportableIncidents", "incidents")).to eq([
      { "summary" => "Phishing", "occurredAt" => "2026-10-01T09:00:00Z", "resolvedAt" => "2026-10-02T09:00:00Z",
        "incidentLessonsLearned" => [ "MFA everywhere" ] }
    ])
    expect(DocumentValidationService.call(JSON.generate(doc), format: "fedramp")).to be_valid
  end

  it "attests to no incidents with an empty list" do
    expect(service.build(service.input).dig("reportableIncidents", "incidents")).to eq([])
  end

  it "issues a report kept exactly as issued, and refuses an overlapping period" do
    report = service.issue(service.input(from: "2026-08-01", to: "2026-10-31", recommendations: [ "Use MFA" ]), user: user)
    expect(report).to have_attributes(issued_by: user, recommendations: [ "Use MFA" ],
                                      sha256: Digest::SHA256.hexdigest(JSON.generate(report.document)))
    expect(report.update(recommendations: [])).to be(false)
    expect(report.reload.recommendations).to eq([ "Use MFA" ])
    expect { service.issue(service.input(from: "2026-10-31"), user: user) }
      .to raise_error(described_class::Error, /after the last report issued, which ended 2026-10-31/)
  end

  it "refuses a period that ends before it starts, in the future, or is not a date" do
    expect { service.input(from: "2026-11-10", to: "2026-11-01") }.to raise_error(described_class::Error, /before it starts/)
    expect { service.input(to: "2026-12-01") }.to raise_error(described_class::Error, /future/)
    expect { service.input(from: "last week") }.to raise_error(described_class::Error, /YYYY-MM-DD/)
  end

  it "needs the overview address the report names" do
    boundary.update!(fedramp_package_overview_uri: nil)
    expect { service.build(service.input) }.to raise_error(FedrampVulnerabilityReportService::MissingPackageOverview)
  end
end
