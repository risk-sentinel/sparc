# frozen_string_literal: true

require "rails_helper"

# #1095 — the POA&M "Risk Status x Impact" heat map derived its COLUMNS from the
# impact values present in the data, so a tier with no rows had no column and an
# empty tier was indistinguishable from one that does not exist. On a risk heat
# map that is backwards: "no highs" is a finding and should be readable as an
# empty column.
#
# The header cell is asserted rather than the bare word because "Low" is a
# substring of "Very Low" and every one of these words appears elsewhere on the
# page (item badges, the filter chips, the legend).
RSpec.describe "POA&M risk heat map levels (#1095)", type: :request do
  let(:user) { create(:user, :admin) }
  let(:poam) { create(:poam_document, name: "Heatmap POAM", status: "completed") }

  before { sign_in_as(user) }

  def header_for(label)
    %(<th class="text-center" style="min-width: 80px;">#{label}</th>)
  end

  # One item, one tier populated. Everything else must still get a column.
  def seed_single_tier!
    create(:poam_item, poam_document: poam, risk_status: "open", impact: "high",
                       title: "Only High Item", row_order: 0)
  end

  it "renders a column for every level in the scale, not only the ones with rows" do
    seed_single_tier!
    get poam_document_path(poam)

    expect(response).to have_http_status(:ok)
    RiskRating::LEVELS.each do |level|
      expect(response.body).to include(header_for(RiskRating.level_label(level))),
        "expected a heat map column for #{level.inspect}, which has no rows"
    end
  end

  it "spells the hyphenated levels properly rather than capitalizing the token" do
    seed_single_tier!
    get poam_document_path(poam)

    expect(response.body).to include(header_for("Very Low"))
    expect(response.body).to include(header_for("Very High"))
    # What `capitalize` produced before this change.
    expect(response.body).not_to include(header_for("Very-low"))
    expect(response.body).not_to include(header_for("Very-high"))
  end

  it "still shows the count in the populated tier" do
    seed_single_tier!
    get poam_document_path(poam)

    expect(response.body).to include("open high: 1 items")
  end

  # The other direction: completing the scale must not silently drop a value
  # that is not part of it. A pre-#1090 "medium" survives on upgraded instances
  # and in imported artifacts.
  it "keeps an unrecognised legacy level visible, appended after the scale" do
    seed_single_tier!
    create(:poam_item, poam_document: poam, risk_status: "open", impact: "medium",
                       title: "Legacy Medium Item", row_order: 1)
    get poam_document_path(poam)

    expect(response.body).to include(header_for("Medium"))
    RiskRating::LEVELS.each do |level|
      expect(response.body).to include(header_for(RiskRating.level_label(level)))
    end
  end

  describe "RiskRating.level_label" do
    it "spells every level in the scale without a hyphen" do
      expect(RiskRating::LEVELS.map { |l| RiskRating.level_label(l) })
        .to eq([ "Very Low", "Low", "Moderate", "High", "Very High" ])
    end

    it "keeps LEVEL_OPTIONS and the labels in agreement" do
      expect(RiskRating::LEVEL_OPTIONS.map(&:first))
        .to eq(RiskRating::LEVELS.map { |l| RiskRating.level_label(l) })
    end
  end
end
