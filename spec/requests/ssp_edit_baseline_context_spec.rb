# frozen_string_literal: true

require "rails_helper"

# The SSP control EDIT panel must show what the author is being asked to answer.
#
# `inline_edit` swaps `view-<id>` for `edit-<id>`, so opening Edit hid the whole
# read view — and with it "What This Baseline Requires", the panel carrying the
# control's own language with this baseline's parameter values applied and its
# implementation sub-parts (#1002). The edit panel put back only
# `guidance_fields`: related controls and supplemental guidance.
#
# The result, reported from a container review: an author writing an
# implementation statement could see commentary ABOUT the control but not the
# control — no statement text, no parameters, no sub-part list.
#
# BOTH panels are asserted here. The read view already had this and a fix that
# moved it rather than duplicating it would satisfy a one-sided test while
# leaving the reader worse off.
RSpec.describe "SSP control edit keeps the baseline context", type: :request do
  let(:admin)     { create(:user, :admin) }
  let!(:catalog)  { create(:control_catalog, name: "NIST 800-53 Rev 5") }
  let!(:family)   { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:cat_ctrl) do
    family.catalog_controls.create!(
      control_id: "ac-1",
      title: "Policy and Procedures",
      # BaselineControlDetail#statement reads guidance_data["statement"], not
      # `description` — the column holds the catalog's own prose, the guidance
      # hash holds the resolvable control language.
      guidance_data: { "statement" => "Develop, document, and disseminate an access control policy." },
      params_data: [ { "id" => "ac-1_prm_1", "label" => "organization-defined personnel" } ]
    )
  end
  # The SSP reaches its catalog through the profile it was authored against —
  # `@catalog_sub_parts` is scoped by `profile_document.control_catalog_id`.
  let!(:profile)  { create(:profile_document, control_catalog: catalog) }
  let!(:ssp)      { create(:ssp_document, profile_document: profile) }
  let!(:control)  { ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures") }

  before { sign_in_as(admin) }

  it "renders the baseline panel inside the EDIT panel, not only the read view" do
    get ssp_document_path(ssp)

    expect(response).to have_http_status(:ok)
    body = response.body

    edit_start = body.index("id=\"edit-#{control.id}\"")
    expect(edit_start).to be_present, "the control's edit panel should render"

    edit_panel = body[edit_start..]
    expect(edit_panel).to include("What This Baseline Requires"),
      "the edit panel must show the control language and parameters the author " \
      "is implementing — hiding it is what this spec exists to prevent"
  end

  it "still shows it in the READ view" do
    get ssp_document_path(ssp)

    view_start = response.body.index("id=\"view-#{control.id}\"")
    edit_start = response.body.index("id=\"edit-#{control.id}\"")
    read_panel = response.body[view_start...edit_start]

    expect(read_panel).to include("What This Baseline Requires"),
      "the fix must ADD the panel to edit mode, not move it out of the read view"
  end

  it "carries the control's own statement text, not just guidance" do
    get ssp_document_path(ssp)

    expect(response.body).to include("Develop, document, and disseminate an access control policy.")
  end
end
