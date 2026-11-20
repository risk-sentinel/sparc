# frozen_string_literal: true

require "rails_helper"

# #1354 — a boundary's Received documents page (ReceivedDocumentsController).
# Read needs evidence.read, upload exchange.upload, review exchange.review, all
# on the boundary; the uploader is never offered (or allowed) the decision,
# unless they are the break-glass administrator; a version that fails
# validation is stored and its errors are shown.
#
# NIST SP 800-53: AC-3, AC-5, CA-3, SI-10, AU-12.
RSpec.describe "Received documents (web)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }
  let(:reader) { create(:user).tap { |u| grant(u, "evidence.read", boundary: boundary) } }
  let(:uploader) { create(:user).tap { |u| grant(u, "evidence.read", "exchange.upload", "exchange.review", boundary: boundary) } }
  let(:reviewer) { create(:user).tap { |u| grant(u, "evidence.read", "exchange.review", boundary: boundary) } }
  let(:outsider) { create(:user).tap { |u| grant(u, "evidence.read", "exchange.upload", "exchange.review", boundary: other_boundary) } }
  let(:admin) { create(:user, :admin) }

  def grant(user, *keys, boundary: nil)
    role = create(:role, scope: boundary ? "authorization_boundary" : "instance",
                         permissions: keys.index_with { true })
    create(:user_role, user: user, role: role, authorization_boundary_id: boundary&.id)
  end

  def vdr(description: "Outdated library #{SecureRandom.hex(4)}")
    {
      "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => "2026-10-31T23:59:59Z" },
      "vulnerabilities" => [ {
        "providerTrackingId" => "VULN-1",
        "detection" => { "detectedAt" => "2026-10-02T10:00:00Z", "detectionSource" => "scanner" },
        "vulnerabilityDescription" => description
      } ]
    }
  end

  def upload_file(body, name: "vdr.json")
    Rack::Test::UploadedFile.new(StringIO.new(body.to_json), "application/json", original_filename: name)
  end

  def received(by:, body: vdr)
    ReceivedDocumentService.call(boundary: boundary, bytes: body.to_json, source: "upload", filename: "vdr.json",
                                 content_type: "application/json", received_by: by).document
  end

  let(:index_path) { authorization_boundary_received_documents_path(boundary) }

  describe "reading" do
    it "lists the boundary's versions for an evidence.read holder" do
      doc = received(by: uploader)
      sign_in_as(reader)
      get index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Received documents", "Pending review", "vulnerability-detail-report")
      expect(response.body).not_to include("received-upload-form") # no exchange.upload

      get authorization_boundary_received_document_path(boundary, doc)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(doc.sha256)
    end

    it "refuses a user whose grants are on another boundary, and hides another boundary's version" do
      doc = received(by: uploader)
      sign_in_as(outsider)
      get index_path
      expect(response).to redirect_to(root_path)
      get authorization_boundary_received_document_path(boundary, doc)
      expect(response).to redirect_to(root_path)
      get file_authorization_boundary_received_document_path(boundary, doc)
      expect(response).to redirect_to(root_path)

      sign_in_as(admin)
      get authorization_boundary_received_document_path(other_boundary, doc)
      expect(response).to have_http_status(:not_found)
    end

    it "downloads the exact stored bytes as an attachment" do
      body = vdr
      doc = received(by: uploader, body: body)
      sign_in_as(reader)
      get file_authorization_boundary_received_document_path(boundary, doc)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to start_with("attachment")
      expect(Digest::SHA256.hexdigest(response.body)).to eq(doc.sha256)
    end

    it "links to the page from the boundary's evidence section" do
      sign_in_as(reader)
      get authorization_boundary_path(boundary)
      expect(response.body).to include(index_path)
    end
  end

  describe "uploading" do
    it "stores an upload through ReceivedDocumentService, recording the uploader" do
      sign_in_as(uploader)
      get index_path
      expect(response.body).to include("received-upload-form", "data-controller=\"dropzone\"")

      expect { post index_path, params: { file: upload_file(vdr) } }.to change(ReceivedDocument, :count).by(1)
      doc = ReceivedDocument.last
      expect(response).to redirect_to(authorization_boundary_received_document_path(boundary, doc))
      expect(doc).to have_attributes(source: "upload", received_by: uploader, state: "pending_review",
                                     authorization_boundary: boundary)
    end

    it "stores an invalid upload with its errors, and shows them" do
      sign_in_as(uploader)
      post index_path, params: { file: upload_file(vdr(description: "  ")) }
      doc = ReceivedDocument.last
      expect(doc.state).to eq("invalid")
      expect(flash[:error]).to include("failed validation")

      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).to include("Invalid", "/vulnerabilities/0/vulnerabilityDescription", "required field is blank",
                                       "cannot be accepted")
      expect(response.body).not_to include("data-testid=\"review-accept\"")
    end

    it "reports a byte-identical re-upload as unchanged and stores nothing new" do
      body = vdr
      sign_in_as(uploader)
      post index_path, params: { file: upload_file(body) }
      expect { post index_path, params: { file: upload_file(body) } }.not_to change(ReceivedDocument, :count)
      expect(flash[:warning]).to include("Unchanged")
    end

    it "refuses an upload without exchange.upload" do
      sign_in_as(reviewer)
      expect { post index_path, params: { file: upload_file(vdr) } }.not_to change(ReceivedDocument, :count)
      expect(response).to redirect_to(root_path)
    end

    it "says why a document SPARC cannot read is not received" do
      sign_in_as(uploader)
      file = Rack::Test::UploadedFile.new(StringIO.new("not a document"), "text/plain", original_filename: "x.txt")
      expect { post index_path, params: { file: file } }.not_to change(ReceivedDocument, :count)
      expect(flash[:error]).to start_with("Not received:")
    end
  end

  describe "review and separation of duties" do
    it "offers the decision to a reviewer who did not upload it, and accepts through the review service" do
      doc = received(by: uploader)
      sign_in_as(reviewer)
      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).to include("data-testid=\"review-accept\"", "data-testid=\"review-reject\"")

      post accept_authorization_boundary_received_document_path(boundary, doc)
      expect(doc.reload).to have_attributes(state: "accepted", reviewed_by: reviewer, review_action: "accept")
      expect(AuditEvent.where(action: "received_document_accepted", subject_id: doc.id)).to exist
    end

    it "does not offer the decision to the uploader, and refuses it if they post anyway" do
      doc = received(by: uploader)
      sign_in_as(uploader)
      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).not_to include("data-testid=\"review-accept\"")
      expect(response.body).to include("data-testid=\"review-sod\"")

      post accept_authorization_boundary_received_document_path(boundary, doc)
      expect(doc.reload.state).to eq("pending_review")
      expect(flash[:error]).to include("cannot be decided by the person who uploaded it")
    end

    it "lets the break-glass administrator decide a version they uploaded" do
      doc = received(by: admin)
      sign_in_as(admin)
      get authorization_boundary_received_document_path(boundary, doc)
      expect(response.body).to include("data-testid=\"review-accept\"")
    end

    it "requires a note to respond or reject" do
      doc = received(by: uploader)
      sign_in_as(reviewer)
      post reject_authorization_boundary_received_document_path(boundary, doc), params: { note: "" }
      expect(doc.reload.state).to eq("pending_review")
      expect(flash[:error]).to include("Say why")

      post respond_authorization_boundary_received_document_path(boundary, doc), params: { note: "Send the scan evidence" }
      expect(doc.reload).to have_attributes(state: "responded", review_note: "Send the scan evidence")

      post reject_authorization_boundary_received_document_path(boundary, doc), params: { note: "Out of scope" }
      expect(doc.reload.state).to eq("rejected")
    end

    it "refuses a review without exchange.review" do
      doc = received(by: uploader)
      sign_in_as(reader)
      post accept_authorization_boundary_received_document_path(boundary, doc)
      expect(response).to redirect_to(root_path)
      expect(doc.reload.state).to eq("pending_review")
    end
  end
end
