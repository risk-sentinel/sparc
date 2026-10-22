# frozen_string_literal: true

require "rails_helper"

# #1234 — an import that matched no loaded catalog is shown on the baseline's
# page, and nothing is shown when every import linked.
RSpec.describe "Unlinked profile imports on the baseline page (#1234)", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  it "lists an import that matched no catalog, with its controls" do
    profile = create(:profile_document, import_metadata: {
      "unlinked_imports" => [ { "href" => "#x", "title" => "Org Custom Controls", "control_ids" => %w[dp-1 dp-1.1] } ]
    })

    get profile_document_path(profile)

    expect(response.body).to include('data-testid="unlinked-imports"')
    expect(response.body).to include("Org Custom Controls").and include("dp-1, dp-1.1")
  end

  it "shows nothing when every import linked" do
    profile = create(:profile_document, import_metadata: { "imports" => [ { "href" => "#x", "catalog_id" => 1 } ] })

    get profile_document_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-testid="unlinked-imports"')
  end
end
