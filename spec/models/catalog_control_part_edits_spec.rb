# frozen_string_literal: true

require "rails_helper"

# #1113 — the catalog stored the same prose TWICE and nothing kept them in step.
#
# `guidance_data` (a JSONB blob) was what the edit form wrote;
# `catalog_control_parts` (structured rows) is what the read-only tree renders,
# what SSP/CDEF statements join on by `statement_id`, and what the OSCAL export
# emits. Measured on the seeded Rev 5 catalog, AC-1 held byte-identical content
# in both — 1,498 characters of supplemental guidance — so editing the form left
# the tree directly beneath it, and the export, showing the old prose.
#
# Parts are now authoritative for editing and the blob is a mirror written in the
# same transaction, so a form submit has ONE write path.
RSpec.describe "CatalogControl part-authoritative editing (#1113)" do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }

  let(:control) do
    create(:catalog_control, control_family: family, control_id: "ac-1",
                             guidance_data: { "statement" => "old stmt",
                                              "supplemental_guidance" => "old guidance" }).tap do |cc|
      cc.catalog_control_parts.create!(part_id: "ac-1_smt", part_name: "statement",
                                       prose: "old stmt", row_order: 0, uuid: SecureRandom.uuid)
      cc.catalog_control_parts.create!(part_id: "ac-1_gdn", part_name: "guidance",
                                       prose: "old guidance", row_order: 1, uuid: SecureRandom.uuid)
      cc.catalog_control_parts.create!(part_id: "ac-1_obj.a-1", part_name: "assessment-objective",
                                       label: "AC-01a.[01]", prose: "a policy is documented",
                                       row_order: 2, uuid: SecureRandom.uuid)
    end
  end

  it "writes the PART, which is what the export and downstream statements read" do
    control.apply_part_edits!("ac-1_gdn" => "new guidance")

    expect(control.catalog_control_parts.find_by(part_id: "ac-1_gdn").prose).to eq("new guidance")
  end

  it "mirrors into guidance_data so the twelve blob consumers stay correct" do
    control.apply_part_edits!("ac-1_gdn" => "new guidance", "ac-1_smt" => "new stmt")

    data = control.reload.guidance_hash
    expect(data["supplemental_guidance"]).to eq("new guidance")
    expect(data["statement"]).to eq("new stmt")
  end

  it "leaves the two stores in agreement — the drift this fixes" do
    control.apply_part_edits!("ac-1_gdn" => "edited once")

    part = control.catalog_control_parts.find_by(part_id: "ac-1_gdn").prose
    blob = control.reload.guidance_hash["supplemental_guidance"]
    expect(part).to eq(blob)
  end

  it "renders assessment objectives into the mirrored blob with their labels" do
    control.apply_part_edits!("ac-1_obj.a-1" => "an access control policy is documented")

    expect(control.reload.guidance_hash["assessment_objective"])
      .to include("AC-01a.[01]", "an access control policy is documented")
  end

  it "ignores a part id that does not belong to this control" do
    other = create(:catalog_control, control_family: family, control_id: "ac-2")
    other.catalog_control_parts.create!(part_id: "ac-2_gdn", part_name: "guidance",
                                        prose: "untouched", row_order: 0, uuid: SecureRandom.uuid)

    control.apply_part_edits!("ac-2_gdn" => "hijacked")

    expect(other.catalog_control_parts.find_by(part_id: "ac-2_gdn").prose).to eq("untouched")
  end
end
