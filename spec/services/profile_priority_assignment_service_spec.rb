# frozen_string_literal: true

require "rails_helper"

# #1357 — a baseline control's priority comes from its catalog control or not
# at all; SPARC no longer derives one from how many baselines include it.
RSpec.describe ProfilePriorityAssignmentService do
  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog) }

  describe ".assign" do
    %w[P1 P2 P3].each do |priority|
      it "copies the catalog control's #{priority}" do
        cc = create(:catalog_control, control_family: family, priority: priority, baseline_impact: "LOW")
        expect(described_class.assign(cc)).to eq(priority)
      end
    end

    it "normalises the catalog's case and spacing" do
      cc = create(:catalog_control, control_family: family, priority: " p2 ")
      expect(described_class.assign(cc)).to eq("P2")
    end

    it "assigns nothing when the catalog control has no priority, however many baselines include it" do
      [ "LOW, MODERATE, HIGH", "MODERATE, HIGH", "HIGH", nil ].each do |impact|
        cc = create(:catalog_control, control_family: family, priority: nil, baseline_impact: impact)
        expect(described_class.assign(cc)).to be_nil, impact.inspect
      end
    end

    it "assigns nothing for a catalog value outside P1–P3" do
      cc = create(:catalog_control, control_family: family, priority: "P0", baseline_impact: "LOW, MODERATE, HIGH")
      expect(described_class.assign(cc)).to be_nil
    end
  end
end
