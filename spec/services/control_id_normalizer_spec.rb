# frozen_string_literal: true

require "rails_helper"

# #499 slice 2 — ControlIdNormalizer translates control IDs across
# NIST 800-53 revisions by consulting seeded ControlMapping records.
RSpec.describe ControlIdNormalizer do
  let!(:rev4_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 4") }
  let!(:rev5_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5") }

  describe ".translate" do
    context "when from_rev equals to_rev (identity)" do
      it "returns identity translations without touching the DB" do
        # No mapping seeded — would force a passthrough if DB were consulted.
        result = described_class.translate(%w[ac-2 ac-3], from_rev: 5, to_rev: 5)
        expect(result.map(&:source_id)).to eq(%w[ac-2 ac-3])
        expect(result.map(&:target_id)).to eq(%w[ac-2 ac-3])
        expect(result.map(&:relationship)).to all(eq("equal"))
        expect(result.map(&:mapping_id)).to all(be_nil)
      end
    end

    context "when no ControlMapping is seeded for the direction" do
      it "falls back to identity passthrough" do
        result = described_class.translate(%w[ac-2], from_rev: 4, to_rev: 5)
        expect(result.length).to eq(1)
        expect(result.first.target_id).to eq("ac-2")
        expect(result.first.relationship).to eq("equal")
        expect(result.first.mapping_id).to be_nil
      end
    end

    context "with a seeded Rev 4 → Rev 5 ControlMapping" do
      let!(:mapping) do
        ControlMapping.create!(
          name: "NIST SP 800-53 Rev 4 → Rev 5",
          source_catalog: rev4_catalog,
          target_catalog: rev5_catalog,
          status: "complete",
          method_type: "automation"
        )
      end

      before do
        # 1→1 same-id, 1→1 changed-id, and 1→N split case
        ControlMappingEntry.create!(control_mapping: mapping, source_control_id: "ac-2",
                                    target_control_id: "ac-2", relationship: "equivalent",
                                    source_type: "control", target_type: "control", row_order: 0)
        ControlMappingEntry.create!(control_mapping: mapping, source_control_id: "ac-3",
                                    target_control_id: "ac-3", relationship: "equal",
                                    source_type: "control", target_type: "control", row_order: 1)
        # Simulate 1→N: ac-99 (hypothetical Rev 4 withdrawn) maps to two Rev 5 controls
        ControlMappingEntry.create!(control_mapping: mapping, source_control_id: "ac-99",
                                    target_control_id: "ac-2", relationship: "subset",
                                    source_type: "control", target_type: "control", row_order: 2)
        ControlMappingEntry.create!(control_mapping: mapping, source_control_id: "ac-99",
                                    target_control_id: "ac-6", relationship: "subset",
                                    source_type: "control", target_type: "control", row_order: 3)
      end

      it "returns Translation rows with relationship + mapping_id populated" do
        result = described_class.translate(%w[ac-2], from_rev: 4, to_rev: 5)
        expect(result.length).to eq(1)
        t = result.first
        expect(t.source_id).to eq("ac-2")
        expect(t.target_id).to eq("ac-2")
        expect(t.relationship).to eq("equivalent")
        expect(t.mapping_id).to eq(mapping.id)
      end

      it "preserves 1→N (one source row per matching target) instead of collapsing" do
        result = described_class.translate(%w[ac-99], from_rev: 4, to_rev: 5)
        expect(result.length).to eq(2)
        expect(result.map(&:target_id)).to contain_exactly("ac-2", "ac-6")
        expect(result.map(&:relationship)).to all(eq("subset"))
      end

      it "passes source ids through with nil relationship when unmapped" do
        result = described_class.translate(%w[ac-2 zz-9], from_rev: 4, to_rev: 5)
        unmapped = result.find { |t| t.source_id == "zz-9" }
        expect(unmapped.target_id).to eq("zz-9")
        expect(unmapped.relationship).to be_nil
        expect(unmapped.mapping_id).to eq(mapping.id)
      end

      it "normalizes input ids to lowercase" do
        result = described_class.translate([ "AC-2", "AC-3" ], from_rev: 4, to_rev: 5)
        expect(result.map(&:source_id)).to eq(%w[ac-2 ac-3])
        expect(result.map(&:target_id)).to eq(%w[ac-2 ac-3])
      end

      it "batches the entry lookup (single SQL for all source ids — no N+1)" do
        queries = []
        callback = ->(_, _, _, _, payload) { queries << payload[:sql] }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          described_class.translate(%w[ac-2 ac-3 ac-99 zz-1 zz-2], from_rev: 4, to_rev: 5)
        end
        entry_queries = queries.grep(/control_mapping_entries/i)
        expect(entry_queries.length).to eq(1), "expected one batched entry SELECT, got #{entry_queries.length}: #{entry_queries}"
      end
    end

    it "returns [] for empty input" do
      expect(described_class.translate([], from_rev: 4, to_rev: 5)).to eq([])
      expect(described_class.translate(nil, from_rev: 4, to_rev: 5)).to eq([])
    end
  end
end
