# frozen_string_literal: true

require "rails_helper"

# #1114 — an assessment plan must be assessable per OBJECTIVE, not per control.
#
# NIST 800-53A gives each control a tree of determination statements, and each
# leaf is a thing an assessor separately determines. Owner review of the SAP:
# "all assessment objectives are forced into a single objective but there are
# multiple objectives that need to be individually checked."
#
# Every layer needed already existed — `SapControlObjective` with per-objective
# status and assessor fields, `_objectives_table` to render them,
# `ControlObjectiveExtractorService` to walk the tree. The chain broke at ONE
# place, and it was the same lossy-intermediate trap as #1100:
#
#   catalog_control_parts        24 assessment-objective parts for ac-1 (#1113)
#     -> OscalResolvedProfileCatalogService#build_control_parts
#                                emitted ONLY statement + guidance
#     -> resolved_catalog_json   no assessment objectives at all
#     -> ControlObjectiveExtractorService   found 0
#     -> SapControlObjective     0 rows
#     -> sap_generator fell back to a single flattened `objective` string
#
# Measured on the seeded estate before the fix: 288 controls, ZERO objectives.
#
# Resolved through the REAL resolver rather than a hand-written catalog: if the
# resolver drops the objectives again, the extractor has nothing to walk and
# these fail, which is the bug they exist to catch.
RSpec.describe "SAP objectives are extracted per catalog objective part (#1114)" do
  let(:catalog) { create(:control_catalog, name: "Test Catalog") }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:control) do
    family.catalog_controls.create!(
      control_id: "ac-1", title: "Policy and Procedures",
      guidance_data: { "statement" => "a. Develop...", "assessment_objective" => "flattened blob" }
    )
  end

  # The tree as NIST 800-53A ships it: containers with NO prose above the leaves
  # that carry it. Binding to a container renders an empty box (#1113), so the
  # shape matters as much as the count.
  before do
    rows = [
      [ "ac-1_obj",     nil,          "AC-01",       nil,                          "assessment-objective", 0 ],
      [ "ac-1_obj.a",   "ac-1_obj",   "AC-01a.",     nil,                          "assessment-objective", 1 ],
      [ "ac-1_obj.a-1", "ac-1_obj.a", "AC-01a.[01]", "a policy is developed;",     "assessment-objective", 2 ],
      [ "ac-1_obj.a-2", "ac-1_obj.a", "AC-01a.[02]", "the policy is disseminated;", "assessment-objective", 3 ],
      [ "ac-1_obj.b",   "ac-1_obj",   "AC-01b.",     "an official is designated;",  "assessment-objective", 4 ],
      [ "ac-1_asm-ex",  nil,          nil,           "Examine: access control policy",   "assessment-method", 5 ]
    ]
    rows.each do |part_id, parent, label, prose, name, order|
      control.catalog_control_parts.create!(
        part_id: part_id, part_name: name, parent_part_id: parent,
        label: label, prose: prose, row_order: order, uuid: SecureRandom.uuid
      )
    end
  end

  let(:profile) { create(:profile_document, control_catalog: catalog, lifecycle_status: "published") }
  let!(:pctrl)  { profile.profile_controls.create!(control_id: "ac-1", title: "Policy and Procedures") }

  let(:resolved) { JSON.parse(OscalResolvedProfileCatalogService.new(profile).export) }

  describe "the resolved catalog" do
    it "carries the assessment objectives it used to drop" do
      names = resolved.dig("catalog", "groups")&.flat_map { |g| Array(g["controls"]) }
      names ||= Array(resolved.dig("catalog", "controls"))
      node = names.find { |c| c["id"] == "ac-1" }

      part_names = Array(node["parts"]).map { |p| p["name"] }
      expect(part_names).to include("assessment-objective"),
        "the resolved catalog dropped the objectives, so nothing downstream can see them"
    end

    # An objective is assessed BY a method. Carrying the objectives while
    # dropping how they are assessed repeats the same omission one level down.
    it "carries the assessment methods too" do
      node = (resolved.dig("catalog", "groups")&.flat_map { |g| Array(g["controls"]) } ||
              Array(resolved.dig("catalog", "controls"))).find { |c| c["id"] == "ac-1" }

      expect(Array(node["parts"]).map { |p| p["name"] }).to include("assessment-method")
    end

    it "preserves NIST's nesting rather than flattening it" do
      node = (resolved.dig("catalog", "groups")&.flat_map { |g| Array(g["controls"]) } ||
              Array(resolved.dig("catalog", "controls"))).find { |c| c["id"] == "ac-1" }
      obj_root = Array(node["parts"]).find { |p| p["id"] == "ac-1_obj" }

      expect(obj_root).to be_present
      child = Array(obj_root["parts"]).find { |p| p["id"] == "ac-1_obj.a" }
      expect(child).to be_present
      expect(Array(child["parts"]).map { |p| p["id"] })
        .to match_array(%w[ac-1_obj.a-1 ac-1_obj.a-2])
    end
  end

  describe "the extractor reading that catalog" do
    it "finds one objective per part, not one per control" do
      objectives = ControlObjectiveExtractorService.objectives_for_control(resolved, "ac-1")

      expect(objectives.map { |o| o[:objective_id] })
        .to include("ac-1_obj.a-1", "ac-1_obj.a-2", "ac-1_obj.b")
      expect(objectives.size).to be > 1,
        "a control with several determination statements collapsed into one objective"
    end

    it "keeps each objective's label so an assessor can cite it" do
      objectives = ControlObjectiveExtractorService.objectives_for_control(resolved, "ac-1")
      by_id = objectives.index_by { |o| o[:objective_id] }

      expect(by_id["ac-1_obj.a-1"][:label]).to eq("AC-01a.[01]")
      expect(by_id["ac-1_obj.a-1"][:prose]).to eq("a policy is developed;")
    end

    it "records the parent so the tree survives into the assessment" do
      objectives = ControlObjectiveExtractorService.objectives_for_control(resolved, "ac-1")
      by_id = objectives.index_by { |o| o[:objective_id] }

      expect(by_id["ac-1_obj.a-1"][:parent_objective_id]).to eq("ac-1_obj.a")
    end
  end
end
