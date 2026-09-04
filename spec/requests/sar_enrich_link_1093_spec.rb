# frozen_string_literal: true

require "rails_helper"

# #1093 — the only route to /sar_documents/:slug/enrich was wrapped in
# `unless @sar_document.enriched?`, so it disappeared the moment the document
# WAS enriched. The screen was reachable exactly once, and after the first save
# the only way back was to type the URL.
#
# Both directions matter here and the "before" one is easy to lose: the fix must
# not remove the call-to-action from an unenriched document, only stop hiding the
# route from an enriched one.
RSpec.describe "SAR enrich link (#1093)", type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  # `SarDocument#enriched?` is true when a description, any sar_result, any
  # local component or an import_ap_href is present.
  let(:unenriched) { create(:sar_document, name: "Fresh SAR", description: nil) }
  let(:enriched)   { create(:sar_document, name: "Worked SAR", description: "Already enriched") }

  it "offers the route while the document is NOT yet enriched" do
    expect(unenriched.enriched?).to be(false)

    get sar_document_path(unenriched)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(enrich_sar_document_path(unenriched))
    expect(response.body).to include("Enrich")
  end

  it "still offers the route once the document IS enriched" do
    expect(enriched.enriched?).to be(true)

    get sar_document_path(enriched)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(enrich_sar_document_path(enriched))
  end

  it "labels the action for the state it is in" do
    get sar_document_path(unenriched)
    expect(response.body).to include("Enrich")
    expect(response.body).not_to include("Edit Enrichment")

    get sar_document_path(enriched)
    expect(response.body).to include("Edit Enrichment")
  end

  # The screen itself has always been readable in both states — only the link was
  # conditional. Asserted so a future change cannot "fix" the link by loosening
  # authorization instead.
  it "serves the enrich screen in both states without changing authorization" do
    get enrich_sar_document_path(unenriched)
    expect(response).to have_http_status(:ok)

    get enrich_sar_document_path(enriched)
    expect(response).to have_http_status(:ok)
  end
end
