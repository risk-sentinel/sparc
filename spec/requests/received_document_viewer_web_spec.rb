# frozen_string_literal: true

require "rails_helper"

# #1390 part G — the received-document viewer on a version's page, the
# questions that go with a response, and the review export (web).
#
# Owner decisions (2026-11-23): the change list is the default tab when there
# is a compared version; "Compare with" any other version of the same
# document; an invalid version says what is wrong and what is needed and can
# be responded to or rejected, never accepted; the review is exportable to
# share out of band.
#
# NIST SP 800-53: AC-3, AC-5, SI-10 (provider content escaped), AU-10, AU-12.
RSpec.describe "Received document viewer (web)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:reader) { create(:user).tap { |u| grant(u, "evidence.read", boundary: boundary) } }
  let(:reviewer) { create(:user).tap { |u| grant(u, "evidence.read", "exchange.review", boundary: boundary) } }
  let(:outsider) { create(:user).tap { |u| grant(u, "evidence.read", "exchange.review", boundary: create(:authorization_boundary)) } }

  def grant(user, *keys, boundary: nil)
    role = create(:role, scope: boundary ? "authorization_boundary" : "instance", permissions: keys.index_with { true })
    create(:user_role, user: user, role: role, authorization_boundary_id: boundary&.id)
  end

  def sample(name) = File.read(Rails.root.join("samples/fedramp-package-demo", name))
  def second(type) = File.read(Rails.root.join("spec/fixtures/files/fedramp/viewer", "#{type}.v2.json"))

  def received_doc(bytes)
    ReceivedDocumentService.call(boundary: boundary, bytes: bytes, source: "upload", filename: "doc.json",
                                 content_type: "application/json", received_by: nil).document
  end

  let(:v1) { received_doc(sample("vulnerability-detail-report.json")).tap { |d| ReceivedDocumentReviewService.accept(d, user: reviewer) } }
  let(:v2) { v1 && received_doc(second("vulnerability-detail-report")) }
  let(:page_path) { authorization_boundary_received_document_path(boundary, v2) }

  describe "tabs" do
    it "opens on the change list, with every change linked to its place in the document" do
      sign_in_as(reader)
      get page_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-viewer-tab="changes"', 'data-testid="delta-changes"', "Change list (#{v2.delta_changes.size})")
      expect(response.body).to include("Vulnerabilities › ECW-VULN-0013 › Current rating (N)", "Show in document")
      expect(response.body).not_to include("Ask about this") # a reader cannot decide
    end

    it "renders side by side, this version and the compared version" do
      sign_in_as(reviewer)
      { "side" => "viewer-side", "current" => "viewer-document", "compared" => "viewer-document" }.each do |tab, testid|
        get page_path, params: { tab: tab, changed: "0" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("data-viewer-tab=\"#{tab}\"", "data-testid=\"#{testid}\"")
      end
      get page_path, params: { tab: "current" }
      expect(response.body).to include("ECW-VULN-0014", "New", "Removed in this version", "Ask about this", "N3")
    end

    it "opens a first version on the document itself" do
      first = received_doc(sample("certification-package-overview.json"))
      sign_in_as(reader)
      get authorization_boundary_received_document_path(boundary, first)
      expect(response.body).to include('data-viewer-tab="current"', 'data-testid="viewer-first-version"', "Example Case Manager")
      expect(response.body).not_to include('data-testid="viewer-tab-changes"')
    end

    it "shows a provider's markup as text, never as HTML, and never links an address" do
      doc = JSON.parse(sample("vulnerability-detail-report.json"))
      doc["vulnerabilities"][0]["vulnerabilityDescription"] = "<script>alert('x')</script><a href=\"https://evil.example\">click</a>"
      hostile = received_doc(JSON.generate(doc))
      sign_in_as(reader)
      get authorization_boundary_received_document_path(boundary, hostile), params: { tab: "current", changed: "0" }
      expect(response.body).to include("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;")
      expect(response.body).not_to include("<script>alert(", 'href="https://evil.example"', 'href="https://trust.example.com')
    end
  end

  describe "compare with" do
    let!(:v3) do
      doc = JSON.parse(second("vulnerability-detail-report"))
      doc["reportPeriod"]["to"] = "2026-11-29T23:59:59Z"
      ReceivedDocumentReviewService.accept(v2, user: reviewer)
      received_doc(JSON.generate(doc))
    end

    it "compares with an earlier version on request, says it is not stored, and offers the way back" do
      sign_in_as(reader)
      path = authorization_boundary_received_document_path(boundary, v3)
      get path, params: { compare: v1.id }
      expect(response.body).to include('data-testid="viewer-compare-banner"', "calculated now and is not stored", "Compare with version 2")
      expect { get path, params: { compare: v1.id } }.not_to(change { v3.reload.delta })
    end

    it "ignores a version from another boundary and shows the recorded comparison" do
      foreign = ReceivedDocumentService.call(boundary: create(:authorization_boundary), bytes: sample("vulnerability-detail-report.json"),
                                             source: "upload", filename: "x.json", received_by: nil).document
      sign_in_as(reader)
      get authorization_boundary_received_document_path(boundary, v3), params: { compare: foreign.id }
      expect(response.body).not_to include('data-testid="viewer-compare-banner"')
      expect(response.body).not_to include("value=\"#{foreign.id}\"")
    end
  end

  describe "a version that failed validation" do
    let(:invalid) do
      v1
      received_doc(File.read(Rails.root.join("samples/fedramp-package-demo/invalid/vdr-blank-required-field.json")))
    end

    it "says what is wrong and what is needed, offers Respond and Reject, never Accept" do
      sign_in_as(reviewer)
      get authorization_boundary_received_document_path(boundary, invalid)
      expect(response.body).to include("Vulnerability description is blank.", "FedRAMP&#39;s schema requires it.",
                                       'data-testid="ask-fix-errors"', 'data-testid="review-respond"', 'data-testid="review-reject"',
                                       "cannot be accepted")
      expect(response.body).not_to include('data-testid="review-accept"')
      # "Ask the provider to fix these" adds the ask controls inside the group it
      # names; the group is marked apart from the button (a smoke run caught the
      # button matching its own selector and adding nothing).
      group = Nokogiri::HTML(response.body).at_css('[data-ask-group="validation-errors"]')
      expect(group).to be_present
      expect(group.css("[data-review-questions-target='ask']")).not_to be_empty
      expect(Nokogiri::HTML(response.body).at_css('[data-testid="ask-fix-errors"]')["data-group"]).to eq("validation-errors")
    end

    it "takes a response carrying questions and keeps the version invalid" do
      sign_in_as(reviewer)
      post respond_authorization_boundary_received_document_path(boundary, invalid), params: {
        note: "", questions: [ { pointer: "/vulnerabilities/ECW-VULN-0012/vulnerabilityDescription",
                                 label: "Vulnerabilities › ECW-VULN-0012 › Vulnerability description",
                                 detail: "Vulnerability description is blank.", question: "Please describe it." } ]
      }
      expect(invalid.reload).to have_attributes(state: "invalid", review_action: "respond")
      expect(invalid.questions.first).to include("question" => "Please describe it.")
    end
  end

  describe "review export" do
    before do
      ReceivedDocumentReviewService.respond(v2, user: reviewer, note: "Two questions.", questions: [
        { "pointer" => "/vulnerabilities/ECW-VULN-0013/currentRating", "label" => "Vulnerabilities › ECW-VULN-0013 › Current rating (N)",
          "detail" => "Current rating raised", "before" => "2", "after" => "3", "question" => "Why [did](http://x) it rise?" }
      ])
    end

    it "downloads the review as Markdown and JSON for a reader, and audits each export" do
      sign_in_as(reader)
      expect { get review_export_authorization_boundary_received_document_path(boundary, v2, format: :md) }
        .to change { AuditEvent.where(action: "received_document_review_exported").count }.by(1)
      expect(response.headers["Content-Disposition"]).to include("attachment", ".md")
      expect(response.body).to include("# Review of Vulnerability detail report version 2", "## Questions for the provider",
                                       "Why \\[did\\]\\(http://x\\) it rise?", v2.sha256)

      get review_export_authorization_boundary_received_document_path(boundary, v2, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("sparc_review_export" => "1")
      expect(json.dig("document", "sha256")).to eq(v2.sha256)
      expect(json.dig("compared_with", "id")).to eq(v1.id)
      expect(json["questions"].first).to include("question" => "Why [did](http://x) it rise?")
    end

    it "refuses the export outside the boundary, in either format" do
      sign_in_as(outsider)
      get review_export_authorization_boundary_received_document_path(boundary, v2, format: :json)
      expect(response).to have_http_status(:forbidden)
      get review_export_authorization_boundary_received_document_path(boundary, v2, format: :md)
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include(v2.sha256)
      expect(AuditEvent.where(action: "received_document_review_exported")).not_to exist
    end
  end
end
