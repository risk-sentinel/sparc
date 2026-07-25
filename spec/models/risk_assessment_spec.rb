# frozen_string_literal: true

require "rails_helper"

RSpec.describe RiskAssessment do
  it "has a valid factory" do
    expect(build(:risk_assessment)).to be_valid
  end

  it "requires title, rationale, and assessor" do
    expect(build(:risk_assessment, title: nil)).not_to be_valid
    expect(build(:risk_assessment, rationale: nil)).not_to be_valid
    expect(build(:risk_assessment, assessed_by: nil)).not_to be_valid
  end

  it "rejects an unknown severity" do
    expect(build(:risk_assessment, original_severity: "SEVERE")).not_to be_valid
  end

  it "requires adjusted_severity to rank below original_severity" do
    expect(build(:risk_assessment, original_severity: "HIGH", adjusted_severity: "LOW")).to be_valid
    expect(build(:risk_assessment, original_severity: "LOW", adjusted_severity: "HIGH")).not_to be_valid
    expect(build(:risk_assessment, original_severity: "HIGH", adjusted_severity: "HIGH")).not_to be_valid
  end

  it "generates a slug from the title" do
    ra = create(:risk_assessment, title: "Downgrade CVE-2026-1 severity")
    expect(ra.slug).to eq("downgrade-cve-2026-1-severity")
  end

  it "can be the linked_subject of a riskAdjustment disposition" do
    disp = create(:finding_disposition, :risk_adjustment)
    expect(disp.linked_subject).to be_a(described_class)
  end
end
