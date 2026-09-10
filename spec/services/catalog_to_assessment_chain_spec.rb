# frozen_string_literal: true

require "rails_helper"

# #1114 — the last two acceptance criteria, end to end.
#
# NIST's model is a chain: Catalog -> Profile -> SSP -> Assessment Plan ->
# Assessment Results. Each layer imports the one below, and a profile "tailors by
# modifying statements, parameters and assessment actions". Two consequences have
# to hold, and neither was proven by anything:
#
#   1. A control the profile TAILORED OUT must not appear in a generated plan.
#      SPARC used to read `CatalogControl` directly, which made this impossible
#      to guarantee — the catalog does not know what a baseline selected.
#   2. An edit to a catalog objective must REACH a newly generated plan. #1113
#      made objectives editable; that is half a feature if the edit stops at the
#      catalog.
#
# Resolved through the REAL resolver rather than a hand-written catalog, so if
# any layer drops the objectives these fail — which is the point.
RSpec.describe "Catalog edits reach the assessment (#1114)" do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }

  def catalog_control(control_id, objective_prose)
    family.catalog_controls.create!(control_id: control_id, title: control_id.upcase).tap do |cc|
      cc.catalog_control_parts.create!(
        part_id: "#{control_id}_obj", part_name: "assessment-objective",
        label: control_id.upcase, prose: nil, row_order: 0, uuid: SecureRandom.uuid
      )
      cc.catalog_control_parts.create!(
        part_id: "#{control_id}_obj.a-1", part_name: "assessment-objective",
        parent_part_id: "#{control_id}_obj", label: "#{control_id.upcase}a.[01]",
        prose: objective_prose, row_order: 1, uuid: SecureRandom.uuid
      )
    end
  end

  # Two controls in the CATALOG; the profile selects only one of them.
  let!(:selected)    { catalog_control("ac-1", "a policy is developed") }
  let!(:tailored_out) { catalog_control("ac-99", "something the baseline excludes") }

  let(:profile) { create(:profile_document, control_catalog: catalog, lifecycle_status: "published") }
  let!(:pctrl)  { profile.profile_controls.create!(control_id: "ac-1", title: "AC-1") }

  let(:boundary) { create(:authorization_boundary) }

  def resolve!
    profile.update!(resolved_catalog_json: JSON.parse(OscalResolvedProfileCatalogService.new(profile).export))
  end

  def generate_sap
    SapGeneratorService.new(name: "Plan #{SecureRandom.hex(4)}", profile_document: profile,
                            authorization_boundary: boundary).generate
  end

  describe "a control the profile tailored out" do
    before { resolve! }

    it "does not appear in a generated assessment plan" do
      sap = generate_sap

      ids = sap.sap_controls.pluck(:control_id).map { |c| ControlId.canonical(c).to_s.downcase }
      expect(ids).to include("ac-1")
      expect(ids).not_to include("ac-99"),
        "the plan included a control the baseline never selected — it is reading the catalog, not the profile"
    end

    it "brings no objectives with it either" do
      sap = generate_sap
      objective_ids = SapControlObjective.joins(:sap_control)
                                         .where(sap_controls: { sap_document_id: sap.id })
                                         .pluck(:objective_id)

      expect(objective_ids).not_to include("ac-99_obj.a-1")
    end
  end

  describe "an edit to a catalog objective" do
    # The whole point of #1113 making objectives editable: the edit has to travel.
    it "reaches a newly generated assessment plan" do
      selected.catalog_control_parts.find_by(part_id: "ac-1_obj.a-1")
              .update!(prose: "EDITED: the policy is reviewed annually")
      resolve!

      sap = generate_sap
      prose = SapControlObjective.joins(:sap_control)
                                 .where(sap_controls: { sap_document_id: sap.id })
                                 .pluck(:prose).compact

      expect(prose).to include("EDITED: the policy is reviewed annually")
    end

    it "reaches a newly generated assessment result" do
      selected.catalog_control_parts.find_by(part_id: "ac-1_obj.a-1")
              .update!(prose: "EDITED: reviewed for the SAR")
      resolve!

      sar = create(:sar_document, profile_document: profile)
      sar.sar_controls.create!(control_id: "ac-1", title: "AC-1", row_order: 0)
      ControlObjectiveExtractorService.new(sar).backfill!

      prose = SarControlObjective.joins(:sar_control)
                                 .where(sar_controls: { sar_document_id: sar.id })
                                 .pluck(:prose).compact

      expect(prose).to include("EDITED: reviewed for the SAR")
    end

    # Provenance: the objective records the catalog part it came from, so an
    # assessor can trace a determination back to the statement that required it.
    it "records the catalog part_id it came from" do
      resolve!
      sap = generate_sap

      ids = SapControlObjective.joins(:sap_control)
                               .where(sap_controls: { sap_document_id: sap.id })
                               .pluck(:objective_id)

      expect(ids).to include("ac-1_obj.a-1"),
        "the objective must carry the catalog's own part id, not a synthesised one"
    end
  end
end
