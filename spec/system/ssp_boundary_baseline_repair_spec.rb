# frozen_string_literal: true

require "rails_helper"

# The production repair journey (reported 2026-09-29), clicked through in a real
# browser under the enforced CSP. The state it starts from — an SSP with no
# boundary — cannot be created through the API or UI since #952, so the
# tests/ui-smoke suite cannot reach it; this is where the new banner control is
# exercised. The control is a plain form: were anything on it blocked by CSP,
# the click would do nothing and the final state below would not be reached.
RSpec.describe "Repairing a boundary-less, unreconciled SSP in the browser", type: :system do
  let(:admin)    { create(:user, :admin) }
  let(:catalog)  { create(:control_catalog) }
  let!(:profile) { create(:profile_document, name: "Rev5 HIGH Baseline", control_catalog: catalog) }
  let!(:boundary) { create(:authorization_boundary, name: "SPARC ECS Deployment") }
  let!(:ssp) do
    build(:ssp_document, name: "SPARC ECS Fargate SSP", slug: "sparc-ecs-fargate-ssp",
                         authorization_boundary: nil, profile_document: nil,
                         import_profile_href: "NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json").tap do |doc|
      doc.save!(validate: false)
      create(:ssp_control, ssp_document: doc, control_id: "ac-1")
    end
  end

  before do
    visit "/login"
    accept_consent_banner
    fill_in "Email Address", with: admin.email
    fill_in "Password",      with: "SecurePassword123!"
    click_button "Sign In"
    expect(page).not_to have_field("Email Address", wait: 5)
  end

  it "sets the baseline, then links the boundary, and the SSP ends up whole" do
    visit ssp_document_path(ssp)
    expect(page).to have_content("Baseline not set")
    expect(page).to have_content("No boundary linked")

    select "Rev5 HIGH Baseline", from: "baseline_profile_document_id"
    click_button "Set baseline"
    expect(page).to have_content("Baseline set")
    expect(page).to have_content(/still needs attention: .*boundary/i)

    select "SPARC ECS Deployment", from: "attach_ssp_document_boundary"
    click_button "Link boundary"
    expect(page).to have_content("is now part of SPARC ECS Deployment")

    expect(ssp.reload.profile_document).to eq(profile)
    expect(ssp.authorization_boundary).to eq(boundary)
    expect(page).not_to have_content("No boundary linked")
    expect(page).not_to have_content("Baseline not set")
  end
end
