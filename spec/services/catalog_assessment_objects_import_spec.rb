# frozen_string_literal: true

require "rails_helper"

# #1114 — `assessment-objects` is where 800-53A says WHAT to examine, and the
# importer dropped it twice over.
#
#   1. It was absent from `CATALOG_PART_NAMES`.
#   2. NIST ships it with NO `id`, so the `part["id"].present?` guard skipped it
#      even once listed.
#
# Verified against the shipped catalog, not invented: in
# `lib/data/catalogs/NIST_SP-800-53_rev5_catalog.json`, ac-1 carries
#
#     assessment-method  ac-1_asm-examine    prose ""
#       assessment-objects  (no id)          prose "Access control policy and
#                                                   procedures; system security
#                                                   plan; ..."
#
# so a plan could say EXAMINE and never say what to examine.
RSpec.describe "Importing 800-53A assessment objects (#1114)" do
  # The exact shape NIST ships, id-less child and all.
  let(:catalog_json) do
    {
      "catalog" => {
        "controls" => [
          { "id" => "ac-1", "title" => "Policy",
            "parts" => [
              { "id" => "ac-1_asm-examine", "name" => "assessment-method",
                "props" => [ { "name" => "method", "value" => "EXAMINE" } ],
                "parts" => [
                  { "name" => "assessment-objects",
                    "prose" => "Access control policy and procedures; system security plan" }
                ] },
              { "id" => "ac-1_asm-interview", "name" => "assessment-method",
                "props" => [ { "name" => "method", "value" => "INTERVIEW" } ],
                "parts" => [
                  { "name" => "assessment-objects",
                    "prose" => "Organizational personnel with access control responsibilities" }
                ] }
            ] }
        ]
      }
    }
  end

  subject(:parts) do
    CatalogPartExtractorService.parts_for_control(
      catalog_json, "ac-1",
      part_names: CatalogPartExtractorService::CATALOG_PART_NAMES
    )
  end

  it "stores the assessment objects at all" do
    objects = parts.select { |p| p[:part_name] == "assessment-objects" }

    expect(objects.size).to eq(2)
    expect(objects.map { |o| o[:prose] })
      .to include("Access control policy and procedures; system security plan")
  end

  # An id-less part cannot be stored, referenced by an assessment, or linked to
  # back-matter, and a NULL id would break the parent/child join the tree needs.
  it "derives an id for the part NIST ships without one" do
    objects = parts.select { |p| p[:part_name] == "assessment-objects" }

    expect(objects.map { |o| o[:part_id] })
      .to match_array(%w[ac-1_asm-examine_objects ac-1_asm-interview_objects])
    expect(objects.map { |o| o[:part_id] }).to all(be_present)
  end

  it "keeps each objects part under the method it belongs to" do
    by_id = parts.index_by { |p| p[:part_id] }

    expect(by_id["ac-1_asm-examine_objects"][:parent_objective_id] ||
           by_id["ac-1_asm-examine_objects"][:parent_part_id]).to eq("ac-1_asm-examine")
    expect(by_id["ac-1_asm-interview_objects"][:parent_part_id]).to eq("ac-1_asm-interview")
  end

  # Deterministic, or a re-import creates a duplicate row every time instead of
  # upserting the same one.
  it "derives the same id on a second pass" do
    first  = parts.map { |p| p[:part_id] }
    second = CatalogPartExtractorService.parts_for_control(
      catalog_json, "ac-1", part_names: CatalogPartExtractorService::CATALOG_PART_NAMES
    ).map { |p| p[:part_id] }

    expect(second).to eq(first)
  end

  it "still carries the method itself, with its EXAMINE/INTERVIEW prop" do
    methods = parts.select { |p| p[:part_name] == "assessment-method" }

    expect(methods.size).to eq(2)
    values = methods.flat_map { |m| Array(m[:props_data]) }
                    .select { |pr| pr["name"] == "method" }.map { |pr| pr["value"] }
    expect(values).to match_array(%w[EXAMINE INTERVIEW])
  end
end
