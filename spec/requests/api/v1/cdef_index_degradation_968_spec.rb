# frozen_string_literal: true

require "rails_helper"

# #968 item 3 — the partial-success contract.
#
# `CdefJsonParserService#index_components` runs the component indexer inside a
# SAVEPOINT and swallows a failure so a document that parsed correctly is not
# lost. That is the right trade, but it left the failure visible only in a log
# line: the API reported a degraded import identically to a clean one, so nobody
# reading the document could tell its component index understates it.
#
# Both directions are asserted deliberately. A field hardcoded to `true` would
# satisfy the degraded case alone, and a field hardcoded to `false` would satisfy
# the healthy case alone; only the pair pins the behaviour.
RSpec.describe "Api::V1::CdefDocuments component-index degradation (#968)", type: :request do
  let(:admin)        { create(:user, :admin) }
  let(:api_token)    { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def body_for(cdef)
    get api_v1_cdef_document_path(cdef), headers: auth_headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).fetch("data")
  end

  context "when the component index failed during import" do
    let(:cdef) do
      create(:cdef_document).tap do |d|
        d.update_column(
          :import_metadata,
          (d.import_metadata || {}).merge(
            "component_index_failed_at" => "2026-08-31T00:00:00Z",
            "component_index_error"     => "ActiveRecord::RecordNotUnique: duplicate uuid"
          )
        )
      end
    end

    it "reports the document as degraded, with when it happened" do
      data = body_for(cdef)

      expect(data["component_index_degraded"]).to be(true)
      expect(data["component_index_failed_at"]).to eq("2026-08-31T00:00:00Z")
    end
  end

  context "when the import was clean" do
    let(:cdef) { create(:cdef_document) }

    it "reports the document as not degraded" do
      data = body_for(cdef)

      expect(data["component_index_degraded"]).to be(false)
      expect(data["component_index_failed_at"]).to be_nil
    end
  end

  it "is reported on the INDEX too, so a consumer can spot degraded rows in a list" do
    clean    = create(:cdef_document)
    degraded = create(:cdef_document).tap do |d|
      d.update_column(:import_metadata,
                      (d.import_metadata || {}).merge("component_index_failed_at" => "2026-08-31T00:00:00Z"))
    end

    get api_v1_cdef_documents_path, params: { items: 100 }, headers: auth_headers
    expect(response).to have_http_status(:ok)

    rows = JSON.parse(response.body).fetch("data").index_by { |r| r["id"] }
    expect(rows.fetch(degraded.id)["component_index_degraded"]).to be(true)
    expect(rows.fetch(clean.id)["component_index_degraded"]).to be(false)
  end
end
