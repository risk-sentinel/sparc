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

  # One load, read from every angle. The seed writes about 1,800 entries one at
  # a time (some nine seconds), and each of these checks used to load it again
  # to read the same rows. `aggregate_failures` still reports every check that
  # fails, by its own message, rather than stopping at the first.
  it "seeds both directions, linked, typed, inverted, traceable and listed", :aggregate_failures do
    load seed_path
    forward = ControlMapping.find_by(name: "NIST SP 800-53 Rev 5 → Rev 4")
    inverse = ControlMapping.find_by(name: "NIST SP 800-53 Rev 4 → Rev 5")

    # creates both forward and inverse ControlMapping records
    expect(forward).to be_present
    expect(inverse).to be_present

    # links the mappings to the right source/target catalogs
    expect(forward.source_catalog).to eq(rev5_catalog)
    expect(forward.target_catalog).to eq(rev4_catalog)
    expect(inverse.source_catalog).to eq(rev4_catalog)
    expect(inverse.target_catalog).to eq(rev5_catalog)

    # populates ControlMappingEntry rows with NIST IR 8477 relationship types
    relationships = forward.control_mapping_entries.pluck(:relationship).uniq
    expect(relationships).to all(satisfy { |r| %w[equal equivalent subset superset intersects].include?(r) })
    expect(forward.control_mapping_entries.count).to be > 100

    # inverts `superset` relationships into `subset` for the reverse direction
    forward_supersets = forward.control_mapping_entries.where(relationship: "superset").count
    inverse_subsets = inverse.control_mapping_entries.where(relationship: "subset").count
    expect(forward_supersets).to eq(inverse_subsets)
    expect(forward_supersets).to be > 0

    # stamps the source xlsx URL into metadata_extra for audit traceability
    expect(forward.metadata_extra["source_xlsx"]).to include("csrc.nist.gov")
    expect(forward.metadata_extra["source_xlsx"]).to include("comparison-workbook.xlsx")

    # User-facing surface check — the seeded records appear on /control_mappings
    # (ControlMapping.sorted is the index scope) without any view changes.
    names = ControlMapping.sorted.pluck(:name)
    expect(names).to include("NIST SP 800-53 Rev 5 → Rev 4")
    expect(names).to include("NIST SP 800-53 Rev 4 → Rev 5")
  end

  it "is idempotent on re-run (no duplicate entries)" do
    load seed_path
    first_count = ControlMappingEntry.count
    load seed_path
    second_count = ControlMappingEntry.count
    expect(second_count).to eq(first_count)
  end

  context "when the Rev 4 or Rev 5 catalog is missing" do
    before { ControlCatalog.destroy_all }

    it "skips gracefully without raising" do
      expect { load seed_path }.not_to raise_error
      expect(ControlMapping.count).to eq(0)
    end
  end
end
