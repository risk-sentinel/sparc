# frozen_string_literal: true

require "rails_helper"

# #1390 — incidents: the record of each evaluation, when each report is due
# by class and N-rating, and the Incident Report.
RSpec.describe FedrampIncidentService do
  include ActiveSupport::Testing::TimeHelpers

  let(:klass) { "C" }
  let(:boundary) do
    create(:authorization_boundary, fedramp_enabled: true, fedramp_package_overview_uri: "https://trust.example/cpo.json",
                                    fedramp_package: { certification_type: "20x", certification_path: "Program",
                                                       certification_class: klass })
  end
  let(:service) { described_class.new(boundary) }
  let(:user) { create(:user) }

  before { travel_to Time.utc(2026, 11, 20, 12) }

  def record(**attributes) = service.record(attributes: attributes, user: user).incident
  def due(incident) = service.deadlines(incident).to_h { |d| [ d.report_type, [ d.due_at, d.force, d.status ] ] }

  it "treats an unrated reportable incident as N5 and times the Initial report from its evaluation" do
    incident = record(tracking_id: "INC-1", evaluation_completed_at: "2026-11-20T11:00")
    expect(incident.current_rating).to be_nil
    expect(due(incident)["Initial"]).to eq([ Time.utc(2026, 11, 20, 12), "MUST", "due" ]) # Class C, N5: 1 hour
    expect(due(incident)["Ongoing"].last).to eq("waiting")
  end

  it "follows the rating's timeframe, and Class A's SHOULD" do
    incident = record(tracking_id: "INC-1", evaluation_completed_at: "2026-11-25T15:00", current_rating: "1")
    expect(due(incident)["Initial"].first).to eq(Time.utc(2026, 11, 27, 15)) # Class C, N1: 1 business day, Thanksgiving skipped

    a = described_class.new(create(:authorization_boundary, fedramp_enabled: true,
                                                            fedramp_package: { certification_type: "20x", certification_path: "Program",
                                                                               certification_class: "A" }))
    incident_a = a.record(attributes: { tracking_id: "INC-A", evaluation_completed_at: "2026-11-20T11:00" }, user: user).incident
    expect(a.deadlines(incident_a).map(&:force)).to eq(%w[SHOULD SHOULD MUST])
  end

  it "keeps the rating history and gives a new rating only when it changes" do
    incident = record(tracking_id: "INC-1", current_rating: "3")
    service.record(incident: incident, attributes: { current_rating: "3" }, user: user)
    service.record(incident: incident, attributes: { current_rating: "2" }, user: user)
    expect(incident.reload.ratings.map { |r| r["rating"] }).to eq([ 3, 2 ])
    expect { service.record(incident: incident, attributes: { current_rating: "9" }, user: user) }
      .to raise_error(described_class::Error, /must be one of 0, 1, 2, 3, 4, 5/)
  end

  it "times Ongoing reports from the last report until resolved, then the Final from the resolution" do
    incident = record(tracking_id: "INC-1", evaluation_completed_at: "2026-11-20T11:00", current_rating: "3")
    service.record_report(incident, type: "Initial", sent_at: "2026-11-20T11:30", user: user)
    expect(due(incident.reload)["Initial"].last).to eq("sent")
    expect(due(incident)["Ongoing"].first(2)).to eq([ Time.utc(2026, 11, 20, 17, 30), "MUST" ]) # Class C, N3: 6 hours

    service.record(incident: incident, attributes: { resolved_at: "2026-11-20T11:45" }, user: user)
    expect(due(incident.reload)["Ongoing"].last).to eq("not_needed")
    expect(due(incident)["Final"].first).to eq(Time.utc(2026, 11, 20, 17, 45))
  end

  it "writes each report, valid against FedRAMP's schema, and the Final only once resolved" do
    incident = record(tracking_id: "INC-1", description: "Credential stuffing", detected_at: "2026-11-20T09:00",
                      evaluation_completed_at: "2026-11-20T10:00", current_rating: "4",
                      milestones: [ { occurred_at: "2026-11-20T09:30", description: "Contained" } ],
                      affected_agencies: "DHS\nGSA\n", indicators: "203.0.113.7", related_cve_ids: "cve-2026-1234")
    service.record(incident: incident, attributes: { current_rating: "2" }, user: user)
    doc = service.report(incident.reload, "Initial")
    expect(doc).to include("reportType" => "Initial", "providerTrackingId" => "INC-1",
                           "affectedAgencies" => %w[DHS GSA], "relatedCveIds" => [ "CVE-2026-1234" ],
                           "potentialImpact" => { "historicalRating" => [ 4 ], "currentRating" => 2 })
    expect(doc["timeline"]["milestones"]).to eq([ { "occurredAt" => "2026-11-20T09:30:00Z", "milestoneDescription" => "Contained" } ])
    expect(DocumentValidationService.call(JSON.generate(doc), format: "fedramp")).to be_valid

    expect { service.report(incident, "Final") }.to raise_error(described_class::Error, /resolved/)
    service.record(incident: incident, attributes: { resolved_at: "2026-11-20T11:00" }, user: user)
    expect(service.report(incident.reload, "Final")["resolvedAt"]).to eq("2026-11-20T11:00:00Z")
    expect { service.report(incident, "Weekly") }.to raise_error(described_class::Error, /report type/)
  end

  it "does not report an incident that is not reportable, and says why it has no deadlines" do
    incident = record(tracking_id: "INC-2", reportable: false)
    expect(service.deadlines(incident)).to eq([])
    expect(service.no_deadlines_reason(incident)).to include("Not a FedRAMP Reportable Incident")
    expect { service.report(incident, "Initial") }.to raise_error(described_class::Error, /not a FedRAMP Reportable/)
  end

  context "without a certification class" do
    let(:klass) { nil }

    it "asks for it before timing reports" do
      expect(service.no_deadlines_reason(record(tracking_id: "INC-3"))).to include("certification class")
    end
  end

  it "refuses a duplicate tracking ID, a bad CVE id and a report sent in the future" do
    incident = record(tracking_id: "INC-1", evaluation_completed_at: "2026-11-20T10:00")
    expect { record(tracking_id: "INC-1") }.to raise_error(described_class::Error, /Tracking has already been taken/)
    expect { record(tracking_id: "INC-4", related_cve_ids: "CVE-26-1") }.to raise_error(described_class::Error, /CVE identifiers/)
    expect { service.record_report(incident, type: "Initial", sent_at: "2026-11-21T12:00", user: user) }
      .to raise_error(described_class::Error, /future/)
  end
end
