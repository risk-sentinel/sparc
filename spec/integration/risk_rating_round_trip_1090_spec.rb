# frozen_string_literal: true

require "rails_helper"

# #1090 — a rating must survive export -> import -> export unchanged.
#
# The defect this pins: both exporters emitted `characterizations_data` and
# nothing else, so `impact`/`likelihood` never left SPARC. Measured on the seeded
# estate before the fix — 6 poam_risks carried a rating, 0 of 16 carried any
# characterizations, so every one of those ratings vanished at export.
#
# The import side always read facets correctly, which is what makes a round trip
# the right shape of test: the two halves must agree, and only an end-to-end
# pass proves they do.
RSpec.describe "risk rating round trip (#1090)", type: :model do
  let(:boundary) { create(:authorization_boundary) }
  let(:document) { create(:sar_document, authorization_boundary: boundary) }
  let(:result)   { create(:sar_result, sar_document: document) }

  def exported_risks(doc)
    json = JSON.parse(OscalSarExportService.new(doc).export_unvalidated)
    json.dig("assessment-results", "results")&.flat_map { |r| Array(r["risks"]) } || []
  end

  it "carries impact and likelihood out, back in, and out again" do
    create(:sar_risk, sar_result: result, title: "Rated risk",
                      impact: "high", likelihood: "moderate")

    first = exported_risks(document)
    facets = first.flat_map { |r| Array(r["characterizations"]).flat_map { |c| c["facets"] } }
    expect(facets.map { |f| [ f["name"], f["value"] ] })
      .to include([ "impact", "high" ], [ "likelihood", "moderate" ])

    # Import that artifact into a NEW document, as an integrator would.
    reimported = create(:sar_document, authorization_boundary: boundary)
    SarJsonParserService.new(reimported, nil)
                        .parse_from_hash(JSON.parse(OscalSarExportService.new(document).export_unvalidated))

    risk = SarRisk.where(sar_result_id: reimported.sar_results.select(:id)).find_by(title: "Rated risk")
    expect(risk).to be_present, "the risk did not survive the import"
    expect(risk.impact).to eq("high")
    expect(risk.likelihood).to eq("moderate")

    # And out again: the second export must say what the first one said.
    second = exported_risks(reimported)
    refacets = second.flat_map { |r| Array(r["characterizations"]).flat_map { |c| c["facets"] } }
    expect(refacets.map { |f| [ f["name"], f["value"] ] })
      .to include([ "impact", "high" ], [ "likelihood", "moderate" ])
  end

  it "does not duplicate the rating on each pass" do
    create(:sar_risk, sar_result: result, title: "Rated once", impact: "low", likelihood: "low")

    reimported = create(:sar_document, authorization_boundary: boundary)
    SarJsonParserService.new(reimported, nil)
                        .parse_from_hash(JSON.parse(OscalSarExportService.new(document).export_unvalidated))

    impacts = exported_risks(reimported)
              .flat_map { |r| Array(r["characterizations"]).flat_map { |c| c["facets"] } }
              .select { |f| f["name"] == "impact" }

    expect(impacts.length).to eq(1),
      "a second export grew the facet list — a round trip must be idempotent"
  end
end
