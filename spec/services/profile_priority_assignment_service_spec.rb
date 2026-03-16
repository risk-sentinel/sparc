# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilePriorityAssignmentService do
  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog) }

  describe ".assign" do
    it "returns explicit P1 priority from catalog control" do
      cc = create(:catalog_control, control_family: family, priority: "P1", baseline_impact: "LOW")
      expect(described_class.assign(cc)).to eq("P1")
    end

    it "returns explicit P2 priority from catalog control" do
      cc = create(:catalog_control, control_family: family, priority: "P2", baseline_impact: "LOW, MODERATE")
      expect(described_class.assign(cc)).to eq("P2")
    end

    it "returns explicit P3 priority from catalog control" do
      cc = create(:catalog_control, control_family: family, priority: "P3")
      expect(described_class.assign(cc)).to eq("P3")
    end

    it "assigns P1 when control has 3 baseline levels" do
      cc = create(:catalog_control, control_family: family, priority: nil, baseline_impact: "LOW, MODERATE, HIGH")
      expect(described_class.assign(cc)).to eq("P1")
    end

    it "assigns P2 when control has 2 baseline levels" do
      cc = create(:catalog_control, control_family: family, priority: nil, baseline_impact: "MODERATE, HIGH")
      expect(described_class.assign(cc)).to eq("P2")
    end

    it "assigns P3 when control has 1 baseline level" do
      cc = create(:catalog_control, control_family: family, priority: nil, baseline_impact: "HIGH")
      expect(described_class.assign(cc)).to eq("P3")
    end

    it "assigns P3 when control has no baseline levels" do
      cc = create(:catalog_control, control_family: family, priority: nil, baseline_impact: nil)
      expect(described_class.assign(cc)).to eq("P3")
    end

    it "ignores non-standard priority values and falls back to heuristic" do
      cc = create(:catalog_control, control_family: family, priority: "P0", baseline_impact: "LOW, MODERATE, HIGH")
      expect(described_class.assign(cc)).to eq("P1")
    end
  end
end
