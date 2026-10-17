# frozen_string_literal: true

require "rails_helper"

# #1218 — the committed worksheets are generated, so they must match what the
# builder produces from the bundled catalog and baselines. A catalog refresh
# that is not followed by `bin/rails samples:odp_worksheets` fails here.
RSpec.describe OdpWorksheetBuilder do
  let(:builder) { described_class.new }
  let(:sheets) { builder.worksheets }

  it "matches the committed files byte for byte" do
    sheets.each do |name, sheet|
      committed = Rails.root.join(described_class::OUTPUT_DIR, name)
      expect(committed).to exist, "#{name} is not committed; run bin/rails samples:odp_worksheets"
      expect(committed.read).to eq(builder.render(sheet)),
        "#{name} is stale; run bin/rails samples:odp_worksheets"
    end
  end

  it "covers the whole catalog and each NIST baseline" do
    counts = sheets.transform_values { |s| s["_about"].slice("controls", "parameters", "selections") }

    expect(counts).to eq(
      "rev5-catalog-odp.json"  => { "controls" => 1196, "parameters" => 1327, "selections" => 131 },
      "rev5-low-odp.json"      => { "controls" => 149,  "parameters" => 364,  "selections" => 41 },
      "rev5-moderate-odp.json" => { "controls" => 287,  "parameters" => 521,  "selections" => 63 },
      "rev5-high-odp.json"     => { "controls" => 370,  "parameters" => 624,  "selections" => 75 }
    )
  end

  it "starts every entry unset, so an untouched entry is skipped rather than written" do
    sheets.each_value do |sheet|
      expect(sheet["parameters"].map { |p| p["value"] }.uniq).to eq([ nil ])
      expect(sheet["selections"].map { |s| s["selected"] }.uniq).to eq([ nil ])
    end
  end

  it "leaves out aggregate parameters and keeps the Rev 4-style alias for reference" do
    catalog = sheets.fetch("rev5-catalog-odp.json")
    ids = catalog["parameters"].map { |p| p["param_id"] } + catalog["selections"].map { |s| s["select_id"] }
    ac1_selection = catalog["selections"].find { |s| s["select_id"] == "ac-01_odp.03" }

    expect(ids).not_to include("ac-1_prm_1") # aggregates ac-01_odp.01 + .02
    expect(catalog["_about"]["aggregate_parameters_omitted"]).to eq(142)
    expect(ac1_selection).to include("alt_identifier" => "ac-1_prm_2",
                                     "choices" => [ "organization-level", "mission/business process-level", "system-level" ])
  end
end
