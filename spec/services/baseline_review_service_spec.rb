# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaselineReviewService do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }

  before do
    create(:catalog_control, control_family: family, control_id: "ac-1", baseline_impact: "LOW, MODERATE, HIGH")
    create(:catalog_control, control_family: family, control_id: "ac-2", baseline_impact: "MODERATE, HIGH")
    create(:catalog_control, control_family: family, control_id: "sc-1", baseline_impact: "HIGH")
  end

  let(:profile) do
    create(:profile_document, control_catalog: catalog, baseline_level: "MODERATE")
  end

  it "diffs selected controls against the expected baseline" do
    profile.profile_controls.create!(control_id: "ac-1", title: "AC-1")  # expected + selected
    profile.profile_controls.create!(control_id: "xx-9", title: "XX-9")  # selected, not expected
    # ac-2 expected at MODERATE but NOT selected → missing

    result = described_class.new(profile).review

    expect(result.level).to eq("MODERATE")
    expect(result.expected_count).to eq(2)         # ac-1, ac-2
    expect(result.selected_count).to eq(2)         # ac-1, xx-9
    expect(result.missing).to eq([ "ac-2" ])
    expect(result.extra).to eq([ "xx-9" ])
    expect(result.selection_matches_baseline?).to be(false)
  end

  it "reports a matching selection" do
    profile.profile_controls.create!(control_id: "ac-1", title: "AC-1")
    profile.profile_controls.create!(control_id: "ac-2", title: "AC-2")

    result = described_class.new(profile).review
    expect(result.selection_matches_baseline?).to be(true)
    expect(result.missing).to be_empty
    expect(result.extra).to be_empty
  end

  it "counts ODP customization vs catalog default labels" do
    default_label = "default label"
    ctrl = profile.profile_controls.create!(control_id: "ac-1", title: "AC-1")
    ctrl.profile_control_fields.create!(field_name: "parameter:ac-1_prm_1", field_value: "custom value")
    ctrl.profile_control_fields.create!(field_name: "parameter_label:ac-1_prm_1", field_value: default_label)
    ctrl.profile_control_fields.create!(field_name: "parameter:ac-1_prm_2", field_value: default_label)
    ctrl.profile_control_fields.create!(field_name: "parameter_label:ac-1_prm_2", field_value: default_label)

    result = described_class.new(profile).review
    expect(result.odp_total_count).to eq(2)
    expect(result.odp_customized_count).to eq(1)
  end

  it "handles a profile with no catalog gracefully" do
    profile.update!(control_catalog: nil)
    result = described_class.new(profile).review
    expect(result.expected_count).to eq(0)
  end
end
