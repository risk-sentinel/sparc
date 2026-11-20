# frozen_string_literal: true

require "rails_helper"

# #1354 — a boundary's received documents: upload, read, download and the
# reviewer's decision. Permissions are per boundary (evidence.read,
# exchange.upload, exchange.review); the uploader cannot decide their own
# upload (AC-5) unless they are the instance administrator.
RSpec.describe "API v1 received documents", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }
  let(:base) { "/api/v1/authorization_boundaries/#{boundary.id}/received_documents" }
  let(:admin) { create(:user, :admin) }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  let(:reader) { user_with({ "evidence.read" => true }) }
  let(:uploader) { user_with({ "evidence.read" => true, "exchange.upload" => true }) }
  let(:reviewer) { user_with({ "evidence.read" => true, "exchange.review" => true }) }
  let(:both) { user_with({ "evidence.read" => true, "exchange.upload" => true, "exchange.review" => true }) }

  def vdr(to: "2026-10-31T23:59:59Z", vulnerabilities: [])
    { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => to },
      "vulnerabilities" => vulnerabilities }.to_json
  end

  def upload(body = vdr, as: uploader, **params)
    query = params.any? ? "?#{params.to_query}" : ""
    post "#{base}#{query}", params: body, headers: headers_for(as).merge("Content-Type" => "application/json")
  end

  def upload_file(body = vdr, as: uploader)
    file = Rack::Test::UploadedFile.new(StringIO.new(body), "application/json", original_filename: "vdr.json")
    post base, params: { file: file }, headers: headers_for(as)
  end

  def stored(user: uploader, body: vdr)
    ReceivedDocumentService.call(boundary: boundary, bytes: body, source: "upload", received_by: user,
                                 filename: "vdr.json", content_type: "application/json").document
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "authorization" do
    it "401s without a token" do
      get base
      expect(response).to have_http_status(:unauthorized)
      post base, params: vdr, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "403s reading without evidence.read on this boundary" do
      outsider = user_with({ "evidence.read" => true }, on: other_boundary)
      get base, headers: headers_for(outsider)
      expect(response).to have_http_status(:forbidden)
      doc = stored
      get "#{base}/#{doc.id}/file", headers: headers_for(outsider)
      expect(response).to have_http_status(:forbidden)
    end

    it "403s an upload without exchange.upload, and stores nothing" do
      expect { upload(as: reader) }.not_to change(ReceivedDocument, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "403s a decision without exchange.review, and the version stays open" do
      doc = stored
      post "#{base}/#{doc.id}/accept", headers: headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/#{doc.id}/reject", params: { note: "no" }, headers: headers_for(uploader), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(doc.reload.state).to eq("pending_review")
    end

    it "404s a version of another boundary named under this one" do
      foreign = ReceivedDocumentService.call(boundary: other_boundary, bytes: vdr, source: "upload").document
      get "#{base}/#{foreign.id}", headers: headers_for(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST (upload)" do
    it "stores a valid upload for review: 201 with the version, the uploader recorded" do
      upload_file
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["status"]).to eq("stored")
      data = body["data"]
      expect(data).to include("source" => "upload", "format" => "fedramp", "document_type" => "vulnerability-detail-report",
                              "state" => "pending_review", "valid" => true, "filename" => "vdr.json",
                              "sha256" => Digest::SHA256.hexdigest(vdr))
      expect(data.dig("received_by", "id")).to eq(uploader.id)
      expect(data.dig("delta", "first_version")).to be(true)
      expect(data["may_decide"]).to be(false)
      expect(AuditEvent.where(action: "received_document_stored").count).to eq(1)
    end

    it "stores an INVALID upload with its errors, visible, 201 (owner, 2026-11-20)" do
      upload(vdr(to: " "))
      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data).to include("state" => "invalid", "valid" => false)
      expect(data.dig("validation", "errors")).to include(a_hash_including("check" => "completeness",
                                                                            "pointer" => "/reportPeriod/to"))
    end

    it "answers 200 unchanged for bytes the stream already holds, and stores nothing new" do
      upload
      first_id = response.parsed_body.dig("data", "id")
      expect { upload }.not_to change(ReceivedDocument, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "unchanged")
      expect(response.parsed_body.dig("data", "id")).to eq(first_id)
    end

    it "takes document_format and document_type" do
      upload(vdr, document_format: "fedramp", document_type: "vulnerability-detail-report")
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "format")).to eq("fedramp")
    end

    it "422s an unknown document_format" do
      upload(vdr, document_format: "docx")
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s an unreadable document and stores nothing" do
      expect {
        post base, params: "not a document", headers: headers_for(uploader).merge("Content-Type" => "text/plain")
      }.not_to change(ReceivedDocument, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("The document could not be received")
    end

    it "422s an empty upload" do
      post base, headers: headers_for(uploader)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("No document supplied")
    end

    it "422s a document over the upload limit" do
      allow(SparcConfig).to receive(:max_upload_bytes).and_return(100)
      upload
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET index / show / file" do
    it "lists the boundary's versions and filters them" do
      valid = stored
      invalid = stored(body: vdr(to: " "))
      ReceivedDocumentService.call(boundary: other_boundary, bytes: vdr, source: "upload")

      get base, headers: headers_for(reader)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |d| d["id"] }).to contain_exactly(valid.id, invalid.id)
      expect(response.parsed_body["meta"]).to include("count" => 2)

      get base, params: { state: "invalid" }, headers: headers_for(reader)
      expect(response.parsed_body["data"].map { |d| d["id"] }).to eq([ invalid.id ])

      get base, params: { document_format: "oscal" }, headers: headers_for(reader)
      expect(response.parsed_body["data"]).to be_empty

      get base, params: { stream: valid.stream_key }, headers: headers_for(reader)
      expect(response.parsed_body["data"].size).to eq(2)
    end

    it "shows a version with its validation, delta, review fields and links" do
      doc = stored(body: vdr(to: " "))
      get "#{base}/#{doc.id}", headers: headers_for(reader)
      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["validation"]["errors"]).not_to be_empty
      expect(data).to include("delta", "review", "counts", "in_effect_version_id")
      expect(data["links"]).to include("file" => "#{base}/#{doc.id}/file", "accept" => "#{base}/#{doc.id}/accept")
    end

    it "sends the exact bytes with their type and SHA-256, and audits the download" do
      doc = stored
      expect {
        get "#{base}/#{doc.id}/file", headers: headers_for(reader)
      }.to change { AuditEvent.where(action: "received_document_downloaded").count }.by(1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(vdr)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["X-Content-SHA256"]).to eq(Digest::SHA256.hexdigest(vdr))
      expect(AuditEvent.where(action: "received_document_downloaded").last.user).to eq(reader)
    end

    it "takes the boundary's slug as well as its id" do
      stored
      get "/api/v1/authorization_boundaries/#{boundary.slug}/received_documents", headers: headers_for(reader)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].size).to eq(1)
    end
  end

  describe "review" do
    it "accepts a version: it takes effect and the decision is recorded and audited" do
      doc = stored
      post "#{base}/#{doc.id}/accept", params: { note: "Reviewed" }, headers: headers_for(reviewer), as: :json
      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data).to include("state" => "accepted", "in_effect_version_id" => doc.id)
      expect(data["review"]).to include("action" => "accept", "note" => "Reviewed")
      expect(data.dig("review", "reviewed_by", "id")).to eq(reviewer.id)
      expect(AuditEvent.where(action: "received_document_accepted").count).to eq(1)
    end

    it "supersedes the version in effect when the next is accepted" do
      first = stored
      ReceivedDocumentReviewService.accept(first, user: reviewer)
      second = stored(body: vdr(to: "2026-10-31T23:00:00Z"))
      expect(second.state).to eq("pending_review")

      post "#{base}/#{second.id}/accept", headers: headers_for(reviewer), as: :json
      expect(response).to have_http_status(:ok)
      expect(first.reload.state).to eq("superseded")
    end

    it "responds and rejects with a note, and 422s either without one" do
      doc = stored
      post "#{base}/#{doc.id}/respond", headers: headers_for(reviewer), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "#{base}/#{doc.id}/respond", params: { note: "Send the scan dates" }, headers: headers_for(reviewer), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "state")).to eq("responded")

      post "#{base}/#{doc.id}/reject", params: { note: "Wrong system" }, headers: headers_for(reviewer), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "state")).to eq("rejected")

      post "#{base}/#{doc.id}/accept", headers: headers_for(reviewer), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s accepting a version that failed validation" do
      doc = stored(body: vdr(to: " "))
      post "#{base}/#{doc.id}/accept", headers: headers_for(reviewer), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(doc.reload.state).to eq("invalid")
    end

    it "403s the uploader deciding their own upload (separation of duties), with the reason" do
      doc = stored(user: both)
      %w[accept respond reject].each do |action|
        post "#{base}/#{doc.id}/#{action}", params: { note: "mine" }, headers: headers_for(both), as: :json
        expect(response).to have_http_status(:forbidden), action
        expect(response.parsed_body["error"]).to include("person who uploaded it")
      end
      expect(doc.reload.state).to eq("pending_review")
    end

    it "shows the uploader may not decide, and another reviewer may" do
      doc = stored(user: both)
      get "#{base}/#{doc.id}", headers: headers_for(both)
      expect(response.parsed_body.dig("data", "may_decide")).to be(false)
      get "#{base}/#{doc.id}", headers: headers_for(reviewer)
      expect(response.parsed_body.dig("data", "may_decide")).to be(true)
    end

    it "lets the instance administrator decide their own upload (break-glass exemption)" do
      doc = stored(user: admin)
      post "#{base}/#{doc.id}/accept", headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:ok)
      expect(doc.reload.state).to eq("accepted")
    end
  end
end
