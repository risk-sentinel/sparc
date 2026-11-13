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

  # #1357 — a priority is optional: an added control takes the catalog's own
  # P1-P3 and is otherwise left unset, never derived.
  it "copies the catalog's own priority to an added control" do
    cc1.update!(priority: "P2")
    described_class.new(profile).update([ "ac-1" ])
    expect(profile.profile_controls.find_by(control_id: "ac-1").priority).to eq("P2")
  end

  it "leaves an added control's priority unset when the catalog has none" do
    cc1.update!(priority: nil, baseline_impact: "L M H")
    cc2.update!(priority: "P0")
    described_class.new(profile).update([ "ac-1", "ac-2" ])
    expect(profile.profile_controls.order(:control_id).pluck(:control_id, :priority))
      .to eq([ [ "ac-1", nil ], [ "ac-2", nil ] ])
  end

  # #1241 — a catalog's assigned value is the catalog's. Copied into the
  # profile it would become tailoring nobody made and be exported as
  # `set-parameters`: the label mistake ClearSeededParameterLabels undid.
  it "leaves a parameter the catalog assigns unset on the baseline" do
    cc1.update!(params_data: [ { "id" => "ac-01_odp.05", "label" => "frequency", "values" => [ "quarterly-invented" ] } ])

    described_class.new(profile).update([ "ac-1" ])
    fields = profile.profile_controls.first.profile_control_fields.to_h { |f| [ f.field_name, f.field_value ] }

    expect(fields).to eq("parameter:ac-01_odp.05" => "", "parameter_label:ac-01_odp.05" => "frequency")
  end

  it "raises without a linked catalog" do
    orphan = create(:profile_document, control_catalog: nil)
    expect { described_class.new(orphan).update([ "ac-1" ]) }
      .to raise_error(described_class::SelectionError, /no source catalog/)
  end
end
