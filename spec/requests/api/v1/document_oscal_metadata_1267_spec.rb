# frozen_string_literal: true

require "rails_helper"

# #1267 — every document type's API writes what its page's metadata forms
# write: name, version, OSCAL Version, Published Date, and the rest of the
# OSCAL metadata under `oscal_metadata`, the name responses already used.
# Before, Published Date was writable on no endpoint, OSCAL Version not on
# SSP/SAR/SAP/POA&M, SAR's version nowhere, and `oscal_metadata` was read-only.
RSpec.describe "Api::V1 document OSCAL metadata (#1267)", type: :request do
  # An admin, because what is under test is which fields each endpoint takes;
  # each controller's write guard has its own specs.
  let(:admin) { create(:user, admin: true) }
  let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'caller').plaintext_token}" } }
  let(:revisions) { [ { "version" => "1.0", "title" => "Invented first issue" } ] }

  {
    profile_document: [ :profile_documents, :profile_version, :slug ],
    cdef_document: [ :cdef_documents, :cdef_version, :slug ],
    ssp_document: [ :ssp_documents, :ssp_version, :slug ],
    sar_document: [ :sar_documents, :sar_version, :slug ],
    sap_document: [ :sap_documents, :sap_version, :slug ],
    poam_document: [ :poam_documents, :poam_version, :slug ],
    control_catalog: [ :control_catalogs, :version, :id ]
  }.each do |key, (resource, version_field, ident)|
    describe resource.to_s do
      let(:document) do
        key == :control_catalog ? create(key, lifecycle_status: "in_progress") : create(key)
      end
      let(:path) { "/api/v1/#{resource}/#{document.public_send(ident)}" }

      it "writes name, version, OSCAL Version, Published Date and OSCAL metadata" do
        put path, headers: headers, as: :json, params: { key => {
          name: "Invented Renamed Document",
          version_field => "2.1",
          oscal_version: "1.1.3",
          published: "2026-10-01T00:00:00Z",
          oscal_metadata: { remarks: "Invented remarks", revisions: revisions }
        } }

        expect(response).to have_http_status(:ok), response.body
        document.reload
        expect(document.name).to eq("Invented Renamed Document")
        expect(document.public_send(version_field)).to eq("2.1")
        expect(document.oscal_version).to eq("1.1.3")
        expect(document.published).to eq("2026-10-01T00:00:00Z")
        expect(document.metadata_extra).to include("remarks" => "Invented remarks", "revisions" => revisions)

        data = response.parsed_body["data"]
        expect(data).to include(version_field.to_s => "2.1", "oscal_version" => "1.1.3",
                                "published" => "2026-10-01T00:00:00Z")
      end

      it "keeps the OSCAL metadata keys a request leaves out" do
        document.update!(metadata_extra: (document.metadata_extra || {}).merge("revisions" => revisions))

        put path, headers: headers, as: :json, params: { key => { oscal_metadata: { remarks: "Invented remarks" } } }

        expect(response).to have_http_status(:ok), response.body
        expect(document.reload.metadata_extra).to include("remarks" => "Invented remarks", "revisions" => revisions)
      end

      it "refuses an OSCAL metadata key the form does not edit, and changes nothing" do
        before_description = document.description

        put path, headers: headers, as: :json,
                  params: { key => { description: "Invented change", oscal_metadata: { "not-an-oscal-key" => 1 } } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["details"]).to include("Unrecognized field: oscal_metadata.not-an-oscal-key")
        expect(document.reload.description).to eq(before_description)
      end

      it "refuses OSCAL metadata that is not an object, and changes nothing" do
        before_description = document.description

        put path, headers: headers, as: :json,
                  params: { key => { description: "Invented change", oscal_metadata: "Invented remarks" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["details"]).to include("Unrecognized field: oscal_metadata")
        expect(document.reload.description).to eq(before_description)
      end
    end
  end
end
