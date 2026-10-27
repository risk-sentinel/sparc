# frozen_string_literal: true

require "rails_helper"

# #1089 — adding and removing the baselines a component definition is used
# under, on the web and the API, with the same write permission as any other
# CDEF change (cdef.write), audited.
RSpec.describe "CDEF baselines (#1089)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:cdef) { create(:cdef_document) }
  let(:moderate) { create(:profile_document, name: "Agency Moderate", lifecycle_status: "published") }
  let(:high) { create(:profile_document, name: "Agency High", lifecycle_status: "published") }
  let(:admin) { create(:user, :admin) }

  describe "web" do
    before { sign_in_as(admin) }

    it "lists the baselines, adds one and removes one" do
      cdef.link_profile!(moderate)
      high
      get cdef_document_path(cdef)
      panel = Nokogiri::HTML(response.body).at_css("[data-testid='cdef-baselines']")
      expect(panel.text).to include("Agency Moderate")
      expect(panel.at_css("select[name='profile_document_id'] option[value='#{high.id}']")).to be_present

      post link_profile_cdef_document_path(cdef), params: { profile_document_id: high.id }
      expect(cdef.reload.profile_documents).to contain_exactly(moderate, high)
      expect(AuditEvent.where(action: "cdef_profile_linked").count).to eq(1)

      delete unlink_profile_cdef_document_path(cdef), params: { profile_document_id: moderate.id }
      expect(cdef.reload.profile_documents).to eq([ high ])
      expect(cdef.profile_document).to eq(high)
    end

    it "refuses a viewer without cdef.write" do
      sign_in_as(create(:user))
      post link_profile_cdef_document_path(cdef), params: { profile_document_id: moderate.id }
      expect(cdef.reload.profile_documents).to be_empty
    end
  end

  describe "API" do
    let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'Test').plaintext_token}" } }

    it "reports, adds and removes the baselines" do
      post "/api/v1/cdef_documents/#{cdef.slug}/profiles", params: { profile_document_id: moderate.slug },
                                                          headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post "/api/v1/cdef_documents/#{cdef.slug}/profiles", params: { profile_document_id: high.id },
                                                          headers: headers, as: :json
      expect(JSON.parse(response.body).dig("data", "profile_document_ids")).to eq([ moderate.id, high.id ].sort)

      get "/api/v1/cdef_documents", headers: headers, as: :json
      listed = JSON.parse(response.body)["data"].find { _1["id"] == cdef.id }
      expect(listed["profile_document_ids"]).to eq([ moderate.id, high.id ].sort)

      delete "/api/v1/cdef_documents/#{cdef.slug}/profiles/#{moderate.id}", headers: headers, as: :json
      expect(JSON.parse(response.body).dig("data", "profile_document_ids")).to eq([ high.id ])
    end

    it "answers 404 for a profile that does not exist, or one the CDEF does not use" do
      post "/api/v1/cdef_documents/#{cdef.slug}/profiles", params: { profile_document_id: 0 }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      delete "/api/v1/cdef_documents/#{cdef.slug}/profiles/#{high.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "refuses a caller without cdef.write" do
      reader = create(:user)
      token = ApiToken.generate!(user: reader, name: "Reader").plaintext_token
      post "/api/v1/cdef_documents/#{cdef.slug}/profiles", params: { profile_document_id: moderate.id },
                                                          headers: { "Authorization" => "Bearer #{token}" }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(cdef.reload.profile_documents).to be_empty
    end
  end
end
