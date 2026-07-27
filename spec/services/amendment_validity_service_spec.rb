# frozen_string_literal: true

require "rails_helper"

RSpec.describe AmendmentValidityService do
  let(:profile)  { create(:profile_document, baseline_level: "moderate") }
  let(:boundary) { create(:authorization_boundary, profile_document: profile) }
  let(:run)      { create(:scan_run, authorization_boundary: boundary) }
  let!(:finding) do
    create(:scanner_finding, :failed, scan_run: run, authorization_boundary: boundary,
           control_id: "AC-1", severity: "HIGH")
  end
  let(:disposition) do
    create(:finding_disposition, authorization_boundary: boundary, control_id: "AC-1", kind: "poam")
  end

  it "computes valid_until from the SLA window (Moderate x High default = 30d) from first-discovered" do
    vu = described_class.new(disposition).valid_until
    expect(vu).to be_within(1.day).of(finding.created_at + 30.days)
  end

  it "prefers a provisioned RemediationTimeline row over the built-in default" do
    create(:remediation_timeline, baseline_level: "Moderate", criticality: "High", days: 5)
    vu = described_class.new(disposition).valid_until
    expect(vu).to be_within(1.day).of(finding.created_at + 5.days)
  end

  it "is indefinitely valid (nil valid_until, valid?=true) when backed by an active POA&M" do
    poam = create(:poam_document, authorization_boundary: boundary)
    create(:poam_finding, poam_document: poam, title: "Remediation plan for AC-1")

    svc = described_class.new(disposition)
    expect(svc.valid_until).to be_nil
    expect(svc.valid?).to be(true)
  end

  it "maps MEDIUM severity to the Moderate criticality window" do
    finding.update!(severity: "MEDIUM")
    create(:remediation_timeline, baseline_level: "Moderate", criticality: "Moderate", days: 45)
    expect(described_class.new(disposition).valid_until).to be_within(1.day).of(finding.created_at + 45.days)
  end
end
