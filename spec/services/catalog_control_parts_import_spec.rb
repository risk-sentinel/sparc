# frozen_string_literal: true

require "rails_helper"

# #1100 root cause — `catalog_control_parts` was EMPTY: 0 rows against 4,054
# catalog_controls, with no failure recorded anywhere.
#
# TWO independent defects stacked, and either alone produces the same symptom,
# which is why the table looked simply unused rather than broken:
#
#   1. `CatalogImportService` flattened `ctrl["parts"]` into five named prose
#      fields on `guidance_data` and discarded the tree. The backfill then read
#      `guidance_data["parts"]` — a key nothing has ever written — so it skipped
#      every control and returned 0 without raising. "No parts found" and "no
#      parts stored" are indistinguishable, so #968's failure trace stayed empty.
#
#   2. `walk_parts` filtered on part_names that omitted "item". NIST names a
#      control's statement part "statement" and every sub-part inside it "item",
#      so walking only "statement" captures the CONTAINER and none of the
#      requirements. Measured on the shipped Rev 5 catalog: ac-1 yields 1 part
#      instead of 10.
#
# Downstream that is why every SSP carried exactly one implementation statement
# per control, and why the OSCAL export emitted one `statement` per
# implemented-requirement — schema-valid, and wrong about what was addressed.
RSpec.describe CatalogImportService, "persists the OSCAL parts tree (#1100)" do
  # The real shape, trimmed: a statement container whose children are `item`,
  # nested three deep, exactly as NIST ships ac-1.
  let(:oscal) do
    {
      "catalog" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "Test Catalog", "version" => "1.0", "oscal-version" => "1.2.2" },
        "groups" => [ {
          "id" => "ac", "title" => "Access Control",
          "controls" => [ {
            "id" => "ac-1", "title" => "Policy and Procedures",
            "parts" => [
              { "id" => "ac-1_smt", "name" => "statement",
                "parts" => [
                  { "id" => "ac-1_smt.a", "name" => "item", "prose" => "Develop, document, and disseminate:",
                    "props" => [ { "name" => "label", "value" => "a." } ],
                    "parts" => [
                      { "id" => "ac-1_smt.a.1", "name" => "item", "prose" => "an access control policy that:",
                        "props" => [ { "name" => "label", "value" => "1." } ],
                        "parts" => [
                          { "id" => "ac-1_smt.a.1.a", "name" => "item", "prose" => "Addresses purpose and scope;",
                            "props" => [ { "name" => "label", "value" => "(a)" } ] }
                        ] }
                    ] },
                  { "id" => "ac-1_smt.b", "name" => "item", "prose" => "Designate an official;",
                    "props" => [ { "name" => "label", "value" => "b." } ] }
                ] },
              { "id" => "ac-1_gdn", "name" => "guidance", "prose" => "Supplemental guidance here." }
            ]
          } ]
        } ]
      }
    }.to_json
  end

  def import!
    described_class.new(StringIO.new(oscal), "test_catalog.json").call
  end

  # The importer creates its own catalog from the OSCAL metadata.
  let(:catalog) { ControlCatalog.find_by(name: "Test Catalog") }

  it "stores the statement SUB-PARTS, not only the container" do
    import!

    control = CatalogControl.find_by(control_id: "ac-1")
    ids = control.catalog_control_parts.where(part_name: %w[statement item]).pluck(:part_id).sort

    expect(ids).to eq(%w[ac-1_smt ac-1_smt.a ac-1_smt.a.1 ac-1_smt.a.1.a ac-1_smt.b]),
      "walking only `statement` captures the container and none of the requirements inside it"
  end

  it "records the parent of each sub-part so the tree survives" do
    import!

    parts = CatalogControl.find_by(control_id: "ac-1").catalog_control_parts.index_by(&:part_id)

    expect(parts["ac-1_smt"].parent_part_id).to be_nil
    expect(parts["ac-1_smt.a"].parent_part_id).to eq("ac-1_smt")
    expect(parts["ac-1_smt.a.1"].parent_part_id).to eq("ac-1_smt.a")
    expect(parts["ac-1_smt.a.1.a"].parent_part_id).to eq("ac-1_smt.a.1")
    expect(parts["ac-1_smt.b"].parent_part_id).to eq("ac-1_smt")
  end

  it "keeps the label and prose a reader needs" do
    import!

    part = CatalogControlPart.find_by(part_id: "ac-1_smt.a.1.a")

    expect(part.label).to eq("(a)")
    expect(part.prose).to eq("Addresses purpose and scope;")
  end

  it "is idempotent — a re-import updates rather than duplicating" do
    import!
    before = CatalogControlPart.count
    uuid   = CatalogControlPart.find_by(part_id: "ac-1_smt.a").uuid

    import!

    expect(CatalogControlPart.count).to eq(before)
    expect(CatalogControlPart.find_by(part_id: "ac-1_smt.a").uuid).to eq(uuid),
      "part UUIDs are derived, so a re-import must not change the identity of a " \
      "part an exported document already references (#397)"
  end
end
