# frozen_string_literal: true

require "rails_helper"

# #940 S2 — the readiness card, inline on the boundary show page.
#
# A thin client over BoundaryReadinessService, the same object the API serves,
# so the screen and the endpoint cannot disagree.
RSpec.describe "the readiness card on the boundary screen (#940)", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:user) { create(:user, admin: true) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(user)
  end

  it "renders on the boundary show page" do
    get authorization_boundary_path(boundary)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Adoption readiness")
  end

  it "names every section" do
    get authorization_boundary_path(boundary)

    expect(response.body).to include("Personnel and roles")
    expect(response.body).to include("Security categorization")
    expect(response.body).to include("Components, ports and protocols")
  end

  # `not_modelled` must not read as a failure of the boundary.
  it "labels an unmodelled item 'Not tracked', not as a failure" do
    get authorization_boundary_path(boundary)

    expect(response.body).to include("Not tracked")
  end

  it "links each section to the adoption guide" do
    get authorization_boundary_path(boundary)

    expect(response.body).to include("wiki/Adopting-OSCAL#")
  end

  # The storage vocabulary must never reach the screen.
  it "never renders a raw fips-199-* token" do
    create(:ssp_document, authorization_boundary: boundary)
    SspInformationType.create!(
      ssp_document: boundary.ssp_document, authorization_boundary: boundary,
      uuid: SecureRandom.uuid, title: "T", description: "D",
      confidentiality_impact_selected: "fips-199-high"
    )

    get authorization_boundary_path(boundary)

    expect(response.body).to include("High")
    expect(response.body).not_to include("fips-199")
  end

  it "adds no inline styles — the #1047 ratchet owns that" do
    get authorization_boundary_path(boundary)

    card = response.body[/Adoption readiness.*?<\/table>/m]
    expect(card).to be_present
    expect(card).not_to include("style=")
  end
end
