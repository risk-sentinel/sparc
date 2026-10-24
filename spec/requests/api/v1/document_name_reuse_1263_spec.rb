# frozen_string_literal: true

require "rails_helper"

# #1263 — through the API, as an integrator meets it: delete a document, then
# create or import one with the same name. Both used to fail with "Slug has
# already been taken".
RSpec.describe "Api::V1 reusing a deleted document's name (#1263)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "creates a component definition named like a deleted one" do
    post "/api/v1/cdef_documents", params: { cdef_document: { name: "Invented Directory" } }, headers: headers, as: :json
    first = response.parsed_body["data"]
    delete "/api/v1/cdef_documents/#{first['slug']}", headers: headers
    expect(response).to have_http_status(:ok)

    post "/api/v1/cdef_documents", params: { cdef_document: { name: "Invented Directory" } }, headers: headers, as: :json

    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body.dig("data", "slug")).not_to eq(first["slug"])
  end

  it "imports a profile file named like a deleted profile" do
    file = -> { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/profiles/basic-profile.yaml"), "application/x-yaml") }
    post "/api/v1/profile_documents/import", params: { file: file.call }, headers: headers
    first = response.parsed_body["data"].first
    delete "/api/v1/profile_documents/#{first['slug']}", headers: headers
    expect(response).to have_http_status(:ok)

    post "/api/v1/profile_documents/import", params: { file: file.call }, headers: headers

    expect(response.status).to be_between(200, 299), response.body
    expect(response.parsed_body["data"].first["slug"]).not_to eq(first["slug"])
  end
end
