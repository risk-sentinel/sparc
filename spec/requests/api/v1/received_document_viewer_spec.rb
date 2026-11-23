# frozen_string_literal: true

require "rails_helper"

# #1390 part G — the API side of the received-document viewer, every web
# function with its API equivalent (issue rules): compare with another
# version, questions with a response or rejection, invalid versions answered
# but never accepted, validation guidance, and the review export.
#
# NIST SP 800-53: AC-3, AC-5, AU-10, AU-12, SI-10.
RSpec.describe "API v1 received document viewer", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:base) { "/api/v1/authorization_boundaries/#{boundary.id}/received_documents" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def user_with(permissions, on: boundary)
    create(:user).tap do |user|
      role = create(:role, :authorization_boundary_scoped, permissions: permissions)
      create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    end
  end

  let(:reader) { user_with({ "evidence.read" => true }) }
  let(:reviewer) { user_with({ "evidence.read" => true, "exchange.review" => true }) }
  let(:outsider) { user_with({ "evidence.read" => true, "exchange.review" => true }, on: create(:authorization_boundary)) }

  def sample(name) = File.read(Rails.root.join("samples/fedramp-package-demo", name))
  def second(type) = File.read(Rails.root.join("spec/fixtures/files/fedramp/viewer", "#{type}.v2.json"))

  def received_doc(bytes, into: boundary)
    ReceivedDocumentService.call(boundary: into, bytes: bytes, source: "upload", filename: "doc.json",
                                 content_type: "application/json", received_by: nil).document
  end

  let!(:v1) { received_doc(sample("security-decision-record.json")).tap { |d| ReceivedDocumentReviewService.accept(d, user: reviewer) } }
  let!(:v2) { received_doc(second("security-decision-record")).tap { |d| ReceivedDocumentReviewService.accept(d, user: reviewer) } }
  let!(:v3) do
    doc = JSON.parse(second("security-decision-record"))
    doc["metadata"]["version"] = "1.4.0"
    received_doc(JSON.generate(doc))
  end

  let(:question) do
    { pointer: "/metadata/version", label: "Metadata › Version", detail: "Version: 1.3.0 → 1.4.0", question: "What changed in 1.4.0?" }
  end

  describe "GET .../:id?compare=" do
    it "reports the recorded comparison by default and a calculated one on request" do
      get "#{base}/#{v3.id}", headers: headers_for(reader)
      data = response.parsed_body["data"]
      expect(data["compared_with_id"]).to eq(v2.id)
      expect(data).not_to have_key("comparison")

      get "#{base}/#{v3.id}", params: { compare: v1.id }, headers: headers_for(reader)
      comparison = response.parsed_body.dig("data", "comparison")
      expect(comparison).to include("compared_with_id" => v1.id, "recorded" => false)
      expect(comparison["changes"].map { |c| c["pointer"] }).to include("/metadata/version", "/securityControls/RA-5/controlImplementationStatus")
      expect(comparison["counts"].values.sum).to eq(comparison["changes"].size)
    end

    it "refuses a version of another boundary or one that failed validation" do
      foreign = received_doc(sample("security-decision-record.json"), into: create(:authorization_boundary))
      get "#{base}/#{v3.id}", params: { compare: foreign.id }, headers: headers_for(reader)
      expect(response).to have_http_status(:not_found)

      invalid = received_doc(JSON.generate(JSON.parse(sample("security-decision-record.json")).except("fedRampRequirements")))
      get "#{base}/#{v3.id}", params: { compare: invalid.id }, headers: headers_for(reader)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "questions" do
    it "stores the questions given with a response and returns them" do
      post "#{base}/#{v3.id}/respond", params: { note: "", questions: [ question ] }.to_json,
                                       headers: headers_for(reviewer).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      review = response.parsed_body.dig("data", "review")
      expect(review["action"]).to eq("respond")
      expect(review["questions"]).to eq([ question.stringify_keys ])
    end

    it "refuses a response with neither a note nor a question" do
      post "#{base}/#{v3.id}/respond", params: { note: "" }.to_json,
                                       headers: headers_for(reviewer).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a reviewer of another boundary" do
      post "#{base}/#{v3.id}/respond", params: { note: "x", questions: [ question ] }.to_json,
                                       headers: headers_for(outsider).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:forbidden)
      expect(v3.reload.review_action).to be_nil
    end
  end

  describe "a version that failed validation" do
    let(:invalid) { received_doc(File.read(Rails.root.join("samples/fedramp-package-demo/invalid/sdr-missing-required-field.json"))) }

    it "explains each error, may be responded to or rejected, and is never accepted" do
      get "#{base}/#{invalid.id}", headers: headers_for(reviewer)
      guidance = response.parsed_body.dig("data", "validation", "guidance")
      expect(guidance.first).to include("wrong" => "The document is missing FedRAMP requirements.")
      expect(response.parsed_body.dig("data", "may_decide")).to be(true)

      post "#{base}/#{invalid.id}/accept", headers: headers_for(reviewer)
      expect(response).to have_http_status(:unprocessable_content)

      post "#{base}/#{invalid.id}/reject", params: { note: "Missing required section." }.to_json,
                                           headers: headers_for(reviewer).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(invalid.reload.state).to eq("rejected")
    end
  end

  describe "GET .../:id/review_export" do
    before { ReceivedDocumentReviewService.respond(v3, user: reviewer, note: "See question.", questions: [ question ]) }

    it "returns the review as JSON and as Markdown, and audits each export" do
      expect { get "#{base}/#{v3.id}/review_export.json", headers: headers_for(reader) }
        .to change { AuditEvent.where(action: "received_document_review_exported").count }.by(1)
      data = response.parsed_body["data"]
      expect(data).to include("sparc_review_export" => "1")
      expect(data.dig("compared_with", "id")).to eq(v2.id)
      expect(data["questions"].first).to include("question" => "What changed in 1.4.0?")

      get "#{base}/#{v3.id}/review_export.md", headers: headers_for(reader)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include("## Questions for the provider", "What changed in 1.4.0?")
    end

    it "refuses a caller outside the boundary" do
      get "#{base}/#{v3.id}/review_export.json", headers: headers_for(outsider)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
