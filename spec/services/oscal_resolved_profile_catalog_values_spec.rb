# frozen_string_literal: true

require "rails_helper"

# #1241 — a resolved baseline carries the catalog's assigned `values`, and a
# value the profile sets REPLACES them, so the resolved catalog never states
# one value in `label` and another in `values`. Values are invented.
RSpec.describe OscalResolvedProfileCatalogService do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "EX") }
  let!(:control) do
    create(:catalog_control, control_family: family, control_id: "ex-1", title: "Example Policy",
           guidance_data: { "statement" => "Review {{ insert: param, ex-01_odp.01 }} by {{ insert: param, ex-01_odp.02 }}." },
           params_data: [
             { "id" => "ex-01_odp.01", "label" => "frequency", "values" => [ "quarterly-invented" ] },
             { "id" => "ex-01_odp.02", "label" => "personnel or roles", "values" => [ "Example Agency personnel" ] }
           ])
  end
  let(:profile) { create(:profile_document, control_catalog: catalog) }
  let!(:profile_control) { create(:profile_control, profile_document: profile, control_id: "ex-1") }

  def resolved_params
    doc = JSON.parse(described_class.new(profile).export)
    doc.dig("catalog", "groups").flat_map { |g| g["controls"] }.find { |c| c["id"] == "ex-1" }["params"].index_by { |p| p["id"] }
  end

  it "keeps the catalog's values where the profile sets nothing" do
    expect(resolved_params.dig("ex-01_odp.01", "values")).to eq([ "quarterly-invented" ])
    expect(resolved_params.dig("ex-01_odp.02", "values")).to eq([ "Example Agency personnel" ])
  end

  it "replaces the catalog's values with the profile's, in values and label alike" do
    profile_control.profile_control_fields.create!(field_name: "parameter:ex-01_odp.01", field_value: "monthly-invented")

    param = resolved_params["ex-01_odp.01"]

    expect(param["values"]).to eq([ "monthly-invented" ])
    expect(param["label"]).to eq("monthly-invented")
  end
end
