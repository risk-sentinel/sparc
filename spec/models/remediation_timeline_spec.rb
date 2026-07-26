# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemediationTimeline do
  it "has a valid factory" do
    expect(build(:remediation_timeline)).to be_valid
  end

  it "validates baseline_level, criticality, days" do
    expect(build(:remediation_timeline, baseline_level: "Nope")).not_to be_valid
    expect(build(:remediation_timeline, criticality: "Sev1")).not_to be_valid
    expect(build(:remediation_timeline, days: -1)).not_to be_valid
  end

  it "is unique per (baseline_level, criticality)" do
    create(:remediation_timeline, baseline_level: "High", criticality: "Critical", days: 7)
    dup = build(:remediation_timeline, baseline_level: "High", criticality: "Critical", days: 14)
    expect(dup).not_to be_valid
  end

  describe ".window_days" do
    it "returns the provisioned row when present" do
      create(:remediation_timeline, baseline_level: "High", criticality: "Critical", days: 3)
      expect(described_class.window_days("High", "Critical")).to eq(3)
    end

    it "falls back to the built-in default when unprovisioned" do
      expect(described_class.window_days("Moderate", "High")).to eq(30)
      expect(described_class.window_days("High", "Critical")).to eq(7)
    end

    it "returns nil for an unknown pairing with no default" do
      expect(described_class.window_days("Bogus", "Critical")).to be_nil
    end
  end
end
