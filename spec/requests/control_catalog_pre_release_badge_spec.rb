# frozen_string_literal: true

require "rails_helper"

# #1228 — a catalog carrying NIST's unreleased develop content says so on its
# page, in the catalog list and in the API; any other catalog does not.
RSpec.describe "NIST pre-release flag on catalogs (#1228)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:develop) { create(:control_catalog, name: "Invented develop copy", oscal_uuid: NistCatalogSource::DEVELOP_UUID, status: "completed") }
  let(:other)   { create(:control_catalog, name: "Invented other catalog", status: "completed") }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  it "shows the badge and the commit on the page of a catalog built from NIST's develop branch" do
    get control_catalog_path(develop.url_id)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-testid='nist-pre-release-badge']")&.text).to eq("Pre-release")
    expect(page.at_css("[data-testid='nist-pre-release-note']").text).to include(NistCatalogSource.source_commit.first(8))
  end

  it "shows no badge on any other catalog" do
    get control_catalog_path(other.url_id)

    expect(Nokogiri::HTML(response.body).at_css("[data-testid='nist-pre-release-badge']")).to be_nil
  end

  it "reports the flag in the API" do
    token = ApiToken.generate!(user: admin, name: "Test")
    headers = { "Authorization" => "Bearer #{token.plaintext_token}" }

    flags = [ develop, other ].map do |catalog|
      get "/api/v1/control_catalogs/#{catalog.id}", headers: headers
      JSON.parse(response.body).dig("data", "nist_pre_release")
    end

    expect(flags).to eq([ true, false ])
  end
end
