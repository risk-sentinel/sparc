# frozen_string_literal: true

require "rails_helper"

# #1029 — `GET /api/v1/cdef_documents/:id/export` gained `format` and `validate`.
#
# The OSCAL component definition — the artifact a CDEF exists to produce — could
# be downloaded only in a browser. The web carries five actions for it
# (download_oscal, download_oscal_validated, download_oscal_unvalidated,
# download_yaml, download_xml) because a browser download needs a URL per
# variant; they are one resource in three serialisations with validation as a
# flag, so the API is one endpoint with two parameters.
#
# The happy paths are exercised end to end against a running instance in
# `tests/api/test_cdef_documents.py`, on a real STIG benchmark. What lives here
# is the branching, and in particular the VALIDATION FAILURE path — a document
# that does not conform to the OSCAL schema is hard to produce on demand
# against a live instance, and it is the case where the web path degrades to a
# flash the API cannot use.
RSpec.describe "Api::V1 CDEF export formats", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: SecureRandom.hex(4)).plaintext_token}" }
  end
  let(:cdef) { create(:cdef_document) }
  let(:path) { "/api/v1/cdef_documents/#{cdef.slug}/export" }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "the default" do
    it "still returns SPARC's control-field JSON" do
      # This endpoint predates the parameter and callers depend on its shape,
      # so "no format" must keep meaning what it always meant.
      get path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("controls")
      expect(response.parsed_body).not_to have_key("component-definition")
    end

    it "is the same as asking for it by name" do
      get path, headers: headers
      implicit = response.parsed_body

      get path, params: { format: "fields" }, headers: headers

      expect(response.parsed_body).to eq(implicit)
    end
  end

  describe "format=oscal" do
    it "returns the OSCAL component definition" do
      # validate: false here on purpose. A component definition with no
      # components does not conform to the OSCAL schema, so the validating
      # path correctly refuses an empty document — see the example below. The
      # validating happy path is exercised in tests/api against a real STIG
      # benchmark, which has components to export.
      get path, params: { format: "oscal", validate: "false" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("component-definition")
    end

    it "refuses an EMPTY component definition, because it is not valid OSCAL" do
      # Not a contrived case: a CDEF created through the API and never
      # populated is exactly this, and exporting it as though it were a
      # conformant artifact is how an invalid document reaches a consumer.
      get path, params: { format: "oscal" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["hint"]).to match(/validate=false/)
    end

    it "validates by default, and refuses a document that does not conform" do
      # The property the flag exists for. An API cannot degrade to a flash and
      # a redirect the way the web path does, so a non-conforming document has
      # to be a refusal that says so — not a file the caller discovers is
      # unusable somewhere downstream.
      allow_any_instance_of(OscalComponentDefinitionExportService)
        .to receive(:export).and_raise(OscalValidationError, "control-id: does not match pattern")

      get path, params: { format: "oscal" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/OSCAL schema/i)
      expect(response.parsed_body["details"]).to be_present
      expect(response.parsed_body["hint"]).to match(/validate=false/),
        "the refusal does not tell the caller how to get the document anyway"
    end

    it "skips validation when asked, so the document is still reachable" do
      allow_any_instance_of(OscalComponentDefinitionExportService)
        .to receive(:export).and_raise(OscalValidationError, "should not be called")
      allow_any_instance_of(OscalComponentDefinitionExportService)
        .to receive(:export_unvalidated).and_return({ "component-definition" => { "uuid" => "x" } }.to_json)

      get path, params: { format: "oscal", validate: "false" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("component-definition", "uuid")).to eq("x")
    end
  end

  describe "the other serialisations" do
    it "returns YAML" do
      get path, params: { format: "oscal-yaml", validate: "false" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to start_with("---")
    end

    it "returns XML" do
      get path, params: { format: "oscal-xml", validate: "false" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<?xml")
    end
  end

  describe "refusals" do
    it "names an unknown format and lists what it accepts" do
      get path, params: { format: "carrier_pigeon" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("carrier_pigeon")
      expect(response.parsed_body["expected"]).to include("fields", "oscal", "oscal-yaml", "oscal-xml")
    end

    it "refuses an anonymous caller" do
      get path, params: { format: "oscal" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
