# frozen_string_literal: true

require "rails_helper"

# #1162 — the API must agree with the canonical control-id form the codebase
# already defines, so an identifier is joinable across two documents exported
# at different times.
#
# `ControlId.canonical` itself is untouched: it is schema-validated in every
# OSCAL document SPARC exports (#852), so this is about the API's WRITE and
# FILTER paths agreeing with it, never about changing the form.
#
# The issue's first item was partly misdiagnosed and the specs below assert
# what is actually wrong. `EvidenceControlLink` has canonicalised on write
# since #911, so ids are not "stored in whatever form the caller sent". The
# live defect was that the controller COMPARED the raw payload against that
# canonical storage: the documented call `control_ids[]=AC-1` matched no
# existing link, so every link was marked for destruction and rebuilt on a
# no-op update — and each destroy/create pair rewrites the BackMatterResource
# rows that OSCAL exports reference.
RSpec.describe "Control identifier canonicalisation (#1162)", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "evidence control links" do
    # Seeded through the factory's own transient rather than
    # `:without_control_links`, because Evidence validates that at least one
    # control is linked — unlinked evidence cannot be created at all.
    let(:evidence) { create(:evidence, control_id: "ac-1") }

    before { evidence.evidence_control_links.create!(control_id: "ac-2") }

    def put_control_ids(ids)
      put "/api/v1/evidences/#{evidence.id}",
          params: { evidence: { control_ids: ids } },
          headers: admin_headers
    end

    it "treats the documented uppercase payload as a no-op, not a rebuild" do
      before_ids = evidence.evidence_control_links.pluck(:id).sort

      put_control_ids([ "AC-1", "AC-2" ])

      expect(response).to have_http_status(:ok), response.body
      expect(evidence.evidence_control_links.reload.pluck(:id).sort).to eq(before_ids)
    end

    it "does not churn the links when the padded display form is sent back" do
      before_ids = evidence.evidence_control_links.pluck(:id).sort

      put_control_ids([ "AC-01", "AC-02" ])

      expect(evidence.evidence_control_links.reload.pluck(:id).sort).to eq(before_ids)
    end

    it "collapses two spellings of one control into a single link" do
      put_control_ids([ "AC-1", "ac-1" ])

      stored = evidence.evidence_control_links.reload.map(&:control_id)
      expect(stored).to contain_exactly("ac-1")
    end

    it "still adds a genuinely new control" do
      put_control_ids([ "AC-1", "AC-2", "AU-6" ])

      stored = evidence.evidence_control_links.reload.map(&:control_id).sort
      expect(stored).to eq(%w[ac-1 ac-2 au-6])
    end

    it "still removes a control the caller dropped" do
      put_control_ids([ "AC-1" ])

      expect(evidence.evidence_control_links.reload.map(&:control_id)).to contain_exactly("ac-1")
    end

    # Evidence must support at least one control, so an empty list is refused
    # rather than honoured — and the existing links must survive the refusal,
    # which is the reason the controller marks for destruction instead of
    # destroying up front.
    it "refuses an empty list and leaves the existing links intact" do
      put_control_ids([])

      expect(response).to have_http_status(:unprocessable_content)
      expect(evidence.evidence_control_links.reload.map(&:control_id)).to contain_exactly("ac-1", "ac-2")
    end
  end

  describe "SSP statement endpoints" do
    let(:document)  { create(:ssp_document) }
    let!(:control)  { create(:ssp_control, ssp_document: document, control_id: "ac-2") }
    let!(:statement) { create(:ssp_control_statement, ssp_control: control, row_order: 1) }

    it "publishes the canonical identifier alongside the stored control_id" do
      get "/api/v1/ssp_documents/#{document.slug}/statements", headers: admin_headers

      expect(response).to have_http_status(:ok), response.body
      row = response.parsed_body["data"].first
      expect(row["control_id"]).to eq("ac-2")
      expect(row["identifier"]).to eq("ac-2")
    end

    it "keeps control_id exactly as stored, so existing consumers are unaffected" do
      control.update_column(:control_id, "AC-02")

      get "/api/v1/ssp_documents/#{document.slug}/statements", headers: admin_headers

      row = response.parsed_body["data"].first
      expect(row["control_id"]).to eq("AC-02")
      expect(row["identifier"]).to eq("ac-2")
    end

    # The empty result was indistinguishable from "this SSP does not implement
    # AC-2", which is why this matters more than tidiness.
    it "finds a row stored in the padded form when filtered by the canonical one" do
      control.update_column(:control_id, "AC-02")

      get "/api/v1/ssp_documents/#{document.slug}/statements",
          params: { control_id: "ac-2" }, headers: admin_headers

      expect(response.parsed_body["data"].length).to eq(1)
    end

    it "finds a row stored canonically when filtered by the padded form" do
      get "/api/v1/ssp_documents/#{document.slug}/statements",
          params: { control_id: "AC-02" }, headers: admin_headers

      expect(response.parsed_body["data"].length).to eq(1)
    end

    it "finds a row when filtered by the NIST enhancement spelling" do
      control.update_column(:control_id, "ac-2.1")

      get "/api/v1/ssp_documents/#{document.slug}/statements",
          params: { control_id: "AC-2 (1)" }, headers: admin_headers

      expect(response.parsed_body["data"].length).to eq(1)
    end

    it "still returns nothing for a control the document does not implement" do
      get "/api/v1/ssp_documents/#{document.slug}/statements",
          params: { control_id: "au-6" }, headers: admin_headers

      expect(response.parsed_body["data"]).to be_empty
    end
  end

  # Measured on 4,054 seeded rows: zero blanks. The callback populates it, so
  # this asserts the invariant rather than shipping a backfill for a condition
  # that does not exist.
  describe "catalog control canonical_id" do
    it "is populated on write" do
      family = create(:control_family)
      control = family.catalog_controls.create!(control_id: "AC-02 (1)", title: "Probe")

      expect(control.canonical_id).to eq("ac-2.1")
      expect(control.canonical_identifier).to eq("ac-2.1")
    end
  end
end
