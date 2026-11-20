# frozen_string_literal: true

require "rails_helper"

# #1354 — POST /api/v1/document_validations checks a document and stores
# nothing but an audit record of the result.
RSpec.describe "API v1 document validations", type: :request do
  let(:user)    { create(:user) }
  let(:token)   { ApiToken.generate!(user: user, name: "Validation Test") }
  let(:headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }
  let(:path)    { "/api/v1/document_validations" }

  let(:vdr) do
    {
      "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => "2026-10-31T23:59:59Z" },
      "vulnerabilities" => []
    }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "401s without a token" do
    post path, params: vdr.to_json, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "checks a raw JSON body" do
    post path, params: vdr.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include("valid" => true, "format" => "fedramp", "document_type" => "vulnerability-detail-report")
    expect(body["schema"]["sha256"]).to match(/\A\h{64}\z/)
  end

  it "checks a multipart upload, and reports an invalid document with 200" do
    vdr["reportPeriod"]["to"] = " "
    file = Rack::Test::UploadedFile.new(StringIO.new(vdr.to_json), "application/json", original_filename: "vdr.json")
    post path, params: { file: file }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["valid"]).to be(false)
    expect(response.parsed_body["errors"]).to include(a_hash_including("check" => "completeness",
                                                                       "pointer" => "/reportPeriod/to"))
  end

  it "takes document_format and document_type" do
    post "#{path}?document_format=fedramp&document_type=incident-report",
         params: { "certificationPackageOverviewUri" => "https://x.example/cpo.json" }.to_json,
         headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["document_type"]).to eq("incident-report")
  end

  it "422s on a document it cannot check" do
    post path, params: "not json", headers: headers.merge("Content-Type" => "text/plain")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("The document could not be checked")
  end

  it "422s with no document" do
    post path, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("No document supplied")
  end

  it "audits the result and the document's hash, never its content" do
    expect {
      post path, params: vdr.to_json, headers: headers.merge("Content-Type" => "application/json")
    }.to change { AuditEvent.where(action: "document_validated").count }.by(1)

    event = AuditEvent.where(action: "document_validated").last
    expect(event.user).to eq(user)
    expect(event.metadata).to include("format" => "fedramp", "valid" => true,
                                      "sha256" => Digest::SHA256.hexdigest(vdr.to_json))
    expect(event.metadata.to_json).not_to include("provider.example")
  end
end
