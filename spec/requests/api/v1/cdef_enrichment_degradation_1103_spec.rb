# frozen_string_literal: true

require "rails_helper"

# #1103 — the partial-success contract, applied to NIST enrichment.
#
# Enrichment runs after the parse has already succeeded. If it fails, the
# document and its controls are intact and must not be lost — but the controls
# carry no NIST reference, so the heat map, coverage and inheritance into an SSP
# all read empty while the import looks perfectly healthy. #968 learned exactly
# this with the component index: a log line is not a contract.
#
# Both directions are asserted deliberately. A field hardcoded to `true` would
# satisfy the degraded case alone, and a field hardcoded to `false` the healthy
# case alone; only the pair pins the behaviour.
RSpec.describe "Api::V1::CdefDocuments NIST enrichment degradation (#1103)", type: :request do
  let(:admin)        { create(:user, :admin) }
  let(:api_token)    { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def body_for(cdef)
    get api_v1_cdef_document_path(cdef), headers: auth_headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).fetch("data")
  end

  let(:degraded) do
    create(:cdef_document).tap do |d|
      d.update_column(
        :import_metadata,
        (d.import_metadata || {}).merge(
          "nist_enrichment_failed_at" => "2026-09-20T00:00:00Z",
          "nist_enrichment_error"     => "ActiveRecord::StatementInvalid: converter exploded"
        )
      )
    end
  end

  let(:clean) { create(:cdef_document) }

  context "when enrichment failed during import" do
    it "reports the document as degraded, with when it happened" do
      data = body_for(degraded)

      expect(data["nist_enrichment_degraded"]).to be(true)
      expect(data["nist_enrichment_failed_at"]).to eq("2026-09-20T00:00:00Z")
    end
  end

  context "when the import was clean" do
    it "reports the document as healthy, with no timestamp" do
      data = body_for(clean)

      expect(data["nist_enrichment_degraded"]).to be(false)
      expect(data["nist_enrichment_failed_at"]).to be_nil
    end
  end

  # Index-level, not detail-only. The whole point is that a consumer listing
  # documents can see which ones carry no NIST mapping without opening each one.
  it "exposes the flag on the index as well as the detail endpoint" do
    degraded
    clean

    get api_v1_cdef_documents_path, headers: auth_headers
    expect(response).to have_http_status(:ok)

    rows = JSON.parse(response.body).fetch("data").index_by { |r| r["id"] }
    expect(rows.fetch(degraded.id)["nist_enrichment_degraded"]).to be(true)
    expect(rows.fetch(clean.id)["nist_enrichment_degraded"]).to be(false)
  end

  # The two degradations are independent: a document can have a working
  # component index and unmapped controls, or the reverse. Reporting one as the
  # other would send an operator to the wrong remedy.
  it "does not conflate enrichment degradation with component-index degradation" do
    data = body_for(degraded)

    expect(data["nist_enrichment_degraded"]).to be(true)
    expect(data["component_index_degraded"]).to be(false)
  end
end
