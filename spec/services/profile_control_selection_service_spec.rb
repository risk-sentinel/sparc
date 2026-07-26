# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfileControlSelectionService do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:cc1)    { create(:catalog_control, control_family: family, control_id: "ac-1") }
  let!(:cc2)    { create(:catalog_control, control_family: family, control_id: "ac-2") }
  let(:profile) { create(:profile_document, control_catalog: catalog) }

  it "adds selected controls from the linked catalog" do
    result = described_class.new(profile).update([ "ac-1" ])
    expect(result.added).to eq(1)
    expect(profile.profile_controls.pluck(:control_id)).to contain_exactly("ac-1")
  end

  it "diffs — removes deselected and adds newly selected" do
    described_class.new(profile).update([ "ac-1" ])
    result = described_class.new(profile).update([ "ac-2" ])
    expect(result.added).to eq(1)
    expect(result.removed).to eq(1)
    expect(profile.profile_controls.pluck(:control_id)).to contain_exactly("ac-2")
  end

  it "clears all controls with an empty set" do
    described_class.new(profile).update([ "ac-1", "ac-2" ])
    described_class.new(profile).update([])
    expect(profile.profile_controls.reload).to be_empty
  end

  it "is idempotent when the set is unchanged" do
    described_class.new(profile).update([ "ac-1" ])
    result = described_class.new(profile).update([ "ac-1" ])
    expect(result.added).to eq(0)
    expect(result.removed).to eq(0)
  end

  it "assigns a priority to added controls" do
    described_class.new(profile).update([ "ac-1" ])
    expect(profile.profile_controls.first.priority).to be_present
  end

  it "raises without a linked catalog" do
    orphan = create(:profile_document, control_catalog: nil)
    expect { described_class.new(orphan).update([ "ac-1" ]) }
      .to raise_error(described_class::SelectionError, /no source catalog/)
  end
end
