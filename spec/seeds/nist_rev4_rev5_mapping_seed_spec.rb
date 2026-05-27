# frozen_string_literal: true

require "rails_helper"

# #499 slice 1 — seed loader for the NIST Rev 4 ↔ Rev 5 ControlMapping.
# Verifies the seed is idempotent, creates both directions, derives
# inverse relationships correctly, and gracefully skips when prereqs
# are missing.
RSpec.describe "db/seeds/nist_rev4_rev5_mapping.rb" do
  let(:seed_path) { Rails.root.join("db/seeds/nist_rev4_rev5_mapping.rb") }

  let!(:rev5_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5") }
  let!(:rev4_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 4") }

  before do
    # Suppress puts output from the seed loader.
    allow($stdout).to receive(:puts)
  end

  it "creates both forward and inverse ControlMapping records" do
    load seed_path
    expect(ControlMapping.find_by(name: "NIST SP 800-53 Rev 5 → Rev 4")).to be_present
    expect(ControlMapping.find_by(name: "NIST SP 800-53 Rev 4 → Rev 5")).to be_present
  end

  it "links the mappings to the right source/target catalogs" do
    load seed_path
    forward = ControlMapping.find_by(name: "NIST SP 800-53 Rev 5 → Rev 4")
    inverse = ControlMapping.find_by(name: "NIST SP 800-53 Rev 4 → Rev 5")
    expect(forward.source_catalog).to eq(rev5_catalog)
    expect(forward.target_catalog).to eq(rev4_catalog)
    expect(inverse.source_catalog).to eq(rev4_catalog)
    expect(inverse.target_catalog).to eq(rev5_catalog)
  end

  it "populates ControlMappingEntry rows with NIST IR 8477 relationship types" do
    load seed_path
    forward = ControlMapping.find_by(name: "NIST SP 800-53 Rev 5 → Rev 4")
    relationships = forward.control_mapping_entries.pluck(:relationship).uniq
    expect(relationships).to all(satisfy { |r| %w[equal equivalent subset superset intersects].include?(r) })
    expect(forward.control_mapping_entries.count).to be > 100
  end

  it "inverts `superset` relationships into `subset` for the reverse direction" do
    load seed_path
    forward_supersets = ControlMapping.find_by(name: "NIST SP 800-53 Rev 5 → Rev 4")
                                      .control_mapping_entries
                                      .where(relationship: "superset")
                                      .count
    inverse_subsets = ControlMapping.find_by(name: "NIST SP 800-53 Rev 4 → Rev 5")
                                    .control_mapping_entries
                                    .where(relationship: "subset")
                                    .count
    expect(forward_supersets).to eq(inverse_subsets)
    expect(forward_supersets).to be > 0
  end

  it "is idempotent on re-run (no duplicate entries)" do
    load seed_path
    first_count = ControlMappingEntry.count
    load seed_path
    second_count = ControlMappingEntry.count
    expect(second_count).to eq(first_count)
  end

  it "stamps the source xlsx URL into metadata_extra for audit traceability" do
    load seed_path
    forward = ControlMapping.find_by(name: "NIST SP 800-53 Rev 5 → Rev 4")
    expect(forward.metadata_extra["source_xlsx"]).to include("csrc.nist.gov")
    expect(forward.metadata_extra["source_xlsx"]).to include("comparison-workbook.xlsx")
  end

  context "when the Rev 4 or Rev 5 catalog is missing" do
    before { ControlCatalog.destroy_all }

    it "skips gracefully without raising" do
      expect { load seed_path }.not_to raise_error
      expect(ControlMapping.count).to eq(0)
    end
  end

  # User-facing surface check — confirms the seeded records appear on
  # /control_mappings without any view changes.
  describe "/control_mappings index visibility" do
    it "lists both new mappings via ControlMapping.sorted (the index scope)" do
      load seed_path
      names = ControlMapping.sorted.pluck(:name)
      expect(names).to include("NIST SP 800-53 Rev 5 → Rev 4")
      expect(names).to include("NIST SP 800-53 Rev 4 → Rev 5")
    end
  end
end
