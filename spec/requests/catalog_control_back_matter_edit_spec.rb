# frozen_string_literal: true

require "rails_helper"

# The catalog control EDIT screen 500s as soon as the control has a linked
# back-matter resource.
#
# `app/views/catalog_controls/_form.html.erb` called
# `catalog_control_control_back_matter_link_path(catalog_control, link_record)`.
# That helper has never existed. `catalog_controls` is nested under
# `control_families` with `shallow: true`, so its member routes collapse and the
# DELETE is `control_back_matter_link_path(:id)`. The two-argument nested form
# only exists on the PROFILE side, whose `profile_controls` is NOT shallow —
# which is where the line was copied from when linking shipped (#371,
# 2026-04-13).
#
# WHY IT SURVIVED SO LONG, AND WHY THIS SPEC LOOKS THE WAY IT DOES.
#
# The call sits inside `if link_record`, so it only runs when the control has at
# least ONE linked resource. The demo seed links none, so every screenshot,
# every smoke run and every existing spec rendered the page happily. The bug was
# reachable only by a user who had actually linked something — which is to say,
# by anyone using the feature.
#
# So the LINK is the fixture. A spec that renders this page without one passes
# against the broken code and proves nothing.
RSpec.describe "Catalog control edit with linked back-matter", type: :request do
  let(:admin)    { create(:user, :admin) }
  let!(:catalog) { create(:control_catalog, name: "NIST 800-53 Rev 5") }
  let!(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:control) { family.catalog_controls.create!(control_id: "ac-1", title: "Policy and Procedures") }
  let!(:resource) { create(:back_matter_resource, title: "Access Control Policy") }

  before { sign_in_as(admin) }

  it "renders when the control has NO linked resources" do
    get control_catalog_edit_control_path(catalog, control.control_id)

    expect(response).to have_http_status(:ok)
  end

  it "renders when the control HAS a linked resource — the case that 500'd" do
    ControlBackMatterLink.create!(linkable: control, back_matter_resource: resource)

    get control_catalog_edit_control_path(catalog, control.control_id)

    expect(response).to have_http_status(:ok),
      "the edit screen must render for a control that has linked back-matter; " \
      "this is the state in which the Unlink button is drawn"
    expect(response.body).to include("Access Control Policy")
  end

  it "points Unlink at the SHALLOW member route" do
    link = ControlBackMatterLink.create!(linkable: control, back_matter_resource: resource)

    get control_catalog_edit_control_path(catalog, control.control_id)

    # The route that actually exists. Asserting the PATH rather than the helper
    # name keeps this honest: a helper that does not exist raises, but a helper
    # that exists and builds the wrong URL would still render.
    expect(response.body).to include("/control_back_matter_links/#{link.id}")
  end
end
