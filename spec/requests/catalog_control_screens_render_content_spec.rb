# frozen_string_literal: true

require "rails_helper"

# Two regressions in two days, both found by the owner LOOKING at the screen,
# both invisible to every existing check:
#
#   1. the Statement field was bound to `ac-1_smt`, a CONTAINER with no prose,
#      so a control whose statement is nine paragraphs rendered an empty box
#   2. the control page reported "Sub-parts 3" for a control with nine, because
#      it listed direct children only
#
# Neither is a 500 and neither breaks a model spec — the page renders fine, it
# just does not contain what it is supposed to. A status-only request spec
# passes against both bugs. So these assert on CONTENT.
#
# The fixture mirrors NIST's real shape, which is the thing both bugs missed:
# containers carry no prose, leaves do.
RSpec.describe "Catalog control screens render their content", type: :request do
  let(:admin)     { create(:user, :admin) }
  let!(:catalog)  { create(:control_catalog, name: "NIST 800-53 Rev 5") }
  let!(:family)   { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:control)  { family.catalog_controls.create!(control_id: "ac-1", title: "Policy and Procedures") }

  # Sub-part CONTROLS (separate rows), two levels deep — the "Sub-parts 3 of 9" bug
  let!(:sub_a)    { family.catalog_controls.create!(control_id: "ac-1a", title: "Develop") }
  let!(:sub_a1)   { family.catalog_controls.create!(control_id: "ac-1a.1", title: "Policy") }
  let!(:sub_a1a)  { family.catalog_controls.create!(control_id: "ac-1a.1.(a)", title: "Purpose") }
  let!(:sub_c)    { family.catalog_controls.create!(control_id: "ac-1c", title: "Review") }
  # shares the prefix but is NOT a descendant
  let!(:ac10)     { family.catalog_controls.create!(control_id: "ac-10", title: "Concurrent Session") }

  def part(id, name, prose, parent: nil, label: nil, order: 0)
    control.catalog_control_parts.create!(part_id: id, part_name: name, prose: prose,
                                          parent_part_id: parent, label: label,
                                          row_order: order, uuid: SecureRandom.uuid)
  end

  before do
    # statement tree: root is a CONTAINER with no prose
    part("ac-1_smt",   "statement", nil,                       order: 0)
    part("ac-1_smt.a", "item", "Develop, document, and disseminate a policy",
         parent: "ac-1_smt", label: "a.", order: 1)
    part("ac-1_smt.b", "item", "Designate an official to manage the policy",
         parent: "ac-1_smt", label: "b.", order: 2)
    # objectives: a container and two leaves
    part("ac-1_obj",     "assessment-objective", nil,          label: "AC-01",       order: 3)
    part("ac-1_obj.a-1", "assessment-objective", "a policy is developed and documented",
         parent: "ac-1_obj", label: "AC-01a.[01]", order: 4)
    part("ac-1_obj.a-2", "assessment-objective", "the policy is disseminated",
         parent: "ac-1_obj", label: "AC-01a.[02]", order: 5)
    part("ac-1_gdn", "guidance", "Access control policy addresses the controls in the AC family",
         order: 6)
    sign_in_as(admin)
  end

  describe "the EDIT screen" do
    before { get control_catalog_edit_control_path(catalog, control.control_id) }

    it "renders the statement prose, which lives in the ITEM parts" do
      expect(response.body).to include("Develop, document, and disseminate a policy")
      expect(response.body).to include("Designate an official to manage the policy")
    end

    it "offers a field per statement item, addressed by part id" do
      expect(response.body).to include("catalog_control[part_prose][ac-1_smt.a]")
      expect(response.body).to include("catalog_control[part_prose][ac-1_smt.b]")
    end

    it "does NOT offer a field for the empty statement container" do
      expect(response.body).not_to include("catalog_control[part_prose][ac-1_smt]")
    end

    it "renders the assessment objectives, editable" do
      expect(response.body).to include("a policy is developed and documented")
      expect(response.body).to include("catalog_control[part_prose][ac-1_obj.a-1]")
    end

    it "does NOT offer a field for an objective CONTAINER" do
      expect(response.body).not_to include("catalog_control[part_prose][ac-1_obj]\"")
    end

    it "renders the supplemental guidance from its part" do
      expect(response.body).to include("Access control policy addresses the controls in the AC family")
    end
  end

  describe "the SHOW screen" do
    before { get control_catalog_control_path(catalog, control.control_id) }

    it "lists EVERY sub-part, not just direct children" do
      %w[ac-1a ac-1a.1 ac-1a.1.(a) ac-1c].each do |id|
        expect(response.body).to include(id), "expected sub-part #{id} on the page"
      end
    end

    it "does not list a control that merely shares the prefix" do
      expect(response.body).not_to include(">ac-10<")
    end

    it "shows the statement prose on the card titled Statement" do
      expect(response.body).to include("Develop, document, and disseminate a policy")
    end
  end
end
